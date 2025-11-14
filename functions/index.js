import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getAuth } from "firebase-admin/auth";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import { https } from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import axios from "axios";
import * as cheerio from "cheerio";
import * as pdfParse from "pdf-parse";
import fetch from "node-fetch";
import corsLib from "cors";

const adminApp = initializeApp();
const db = getFirestore(adminApp);
const auth = getAuth(adminApp);
const messaging = getMessaging(adminApp);
const cors = corsLib({ origin: true });

/* -------------------------------------------------------
   Helper: safe send FCM and cleanup invalid tokens
---------------------------------------------------------- */
async function safeSendFCM(message, userId) {
  try {
    const resp = await messaging.send(message);
    logger.log("FCM send success:", resp);
    return { success: true, resp };
  } catch (err) {
    logger.error("FCM send error:", err);
    const code = err?.code || "";
    const msg = err?.message || JSON.stringify(err);

    if (code.includes("registration-token-not-registered") || msg.includes("notRegistered")) {
      if (userId) {
        logger.log(`Removing invalid fcmToken for user ${userId}`);
        try {
          await db.collection("users").doc(userId).update({ fcmToken: null });
        } catch (e) {
          logger.warn("Failed to remove invalid token from user doc:", e);
        }
      }
    }
    return { success: false, error: err };
  }
}

/* -------------------------------------------------------
   Generate Custom Token
---------------------------------------------------------- */
export const getCustomToken = onCall(async (request) => {
  const { phoneNumber } = request.data;
  if (!phoneNumber) throw new HttpsError("invalid-argument", "Phone number is required.");

  let userDoc = await db.collection("users").where("phone", "==", phoneNumber).limit(1).get();
  if (userDoc.empty) {
    userDoc = await db.collection("admins").where("phone", "==", phoneNumber).limit(1).get();
  }
  if (userDoc.empty) throw new HttpsError("not-found", "No account found.");

  const uid = userDoc.docs[0].data().uid;
  if (!uid) throw new HttpsError("not-found", "No UID found.");

  return { token: await auth.createCustomToken(uid) };
});

/* -------------------------------------------------------
   Register FCM Token
---------------------------------------------------------- */
export const registerFcmToken = onCall(async (request) => {
  const { userId, fcmToken } = request.data;
  if (!userId || !fcmToken) throw new HttpsError("invalid-argument", "userId and fcmToken required.");

  await db.collection("users").doc(userId).update({ fcmToken });
  return { success: true, message: "FCM token registered." };
});

/* -------------------------------------------------------
   Manual Notification Sender (Admin)
---------------------------------------------------------- */
export const sendNotification = onCall(async (request) => {
  const { userId, title, body, type = "general", orderId = null } = request.data;
  if (!userId || !title || !body) throw new HttpsError("invalid-argument", "Missing required fields.");

  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "User not found.");

  const fcmToken = userDoc.data().fcmToken;
  const messageId = `manual_${Date.now()}`;

  const message = {
    token: fcmToken,
    notification: { title, body },
    data: {
      type: String(type),
      orderId: orderId ? String(orderId) : "",
      messageId,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      priority: "high",
      notification: { channelId: "daligas_channel", sound: "default" },
    },
  };

  const sendResult = fcmToken ? await safeSendFCM(message, userId) : { success: false };

  await db.collection("users").doc(userId).collection("inAppNotifications").add({
    title, body, type, orderId: orderId || null,
    messageId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  });

  return sendResult.success
    ? { success: true, message: "Sent." }
    : { success: true, message: "Saved in-app only." };
});

/* -------------------------------------------------------
   createOrder — NOW CREATES CHAT + METADATA FOR NOTIFICATIONS
---------------------------------------------------------- */
export const createOrder = onCall(async (request) => {
  const { userId, items, paymentMethod, deliveryAddress } = request.data;
  if (!userId || !items?.length) throw new HttpsError("invalid-argument", "Missing details.");
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");

  try {
    // 1. Assign employee
    const employeesSnap = await db.collection("employees").get();
    if (employeesSnap.empty) throw new HttpsError("failed-precondition", "No employees.");

    let chosenEmployeeId = null, minActiveOrders = Infinity;
    for (const empDoc of employeesSnap.docs) {
      const empId = empDoc.id;
      const activeCount = await db.collection("orders")
        .where("employeeId", "==", empId)
        .where("deliveryStatus", "in", ["Processing", "Shipped"])
        .get().then(s => s.size);
      if (activeCount < minActiveOrders) { minActiveOrders = activeCount; chosenEmployeeId = empId; }
    }

    // 2. Total
    const total = items.reduce((sum, i) => sum + i.price * i.quantity, 0);

    // 3. Create order
    const orderRef = db.collection("orders").doc();
    await orderRef.set({
      orderId: orderRef.id,
      userId,
      employeeId: chosenEmployeeId,
      items,
      total,
      paymentMethod,
      paymentStatus: "Pending",
      deliveryStatus: "Processing",
      deliveryAddress,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 4. Update stock
    await Promise.all(items.map(async (item) => {
      const productRef = db.collection("products").doc(item.productId);
      return db.runTransaction(async (t) => {
        const doc = await t.get(productRef);
        if (!doc.exists) return;
        const stock = Math.max((doc.data().stock || 0) - item.quantity, 0);
        t.update(productRef, { stock });
      });
    }));

    const firstProductName = items[0]?.name || "your item";
    const shortOrderId = orderRef.id.substring(0, 8);
    const messageId = `order_${orderRef.id}`;

    // === CHAT + METADATA CREATION (THIS MAKES NOTIFICATIONS WORK) ===
    const chatId = `${userId}_${chosenEmployeeId}_${orderRef.id}`;
    await db.collection("chats").doc(chatId).set({
      customerId: userId,
      employeeId: chosenEmployeeId,
      orderId: orderRef.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      deletedByCustomer: false,
      deletedByEmployee: false,
    }, { merge: true });

    await db.collection("chats").doc(chatId)
      .collection("metadata")
      .doc("info")
      .set({
        userId: userId,
        employeeId: chosenEmployeeId,
        orderId: orderRef.id,
      });

    // 6. Notify USER
    const userDoc = await db.collection("users").doc(userId).get();
    const userFcmToken = userDoc.data()?.fcmToken;

    if (userFcmToken) {
      await safeSendFCM({
        token: userFcmToken,
        notification: { title: "Order Placed!", body: `"${firstProductName}" ordered (Order #${shortOrderId}).` },
        data: { type: "order", orderId: orderRef.id, messageId, click_action: "FLUTTER_NOTIFICATION_CLICK" },
        android: { priority: "high", notification: { channelId: "daligas_channel" } },
      }, userId);
    }

    await db.collection("users").doc(userId).collection("inAppNotifications").add({
      title: "Order Placed!",
      body: `"${firstProductName}" ordered (Order #${shortOrderId}).`,
      type: "order",
      orderId: orderRef.id,
      messageId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    });

    // 7. Notify EMPLOYEE
    const empDoc = await db.collection("employees").doc(chosenEmployeeId).get();
    const empFcmToken = empDoc.data()?.fcmToken;

    if (empFcmToken) {
      await safeSendFCM({
        token: empFcmToken,
        notification: { title: "New Order Assigned", body: `"${firstProductName}" – Order #${shortOrderId} ready.` },
        data: { type: "order", orderId: orderRef.id, messageId, click_action: "FLUTTER_NOTIFICATION_CLICK" },
        android: { priority: "high", notification: { channelId: "daligas_channel" } },
      }, chosenEmployeeId);
    }

    await db.collection("employees").doc(chosenEmployeeId).collection("inAppNotifications").add({
      title: "New Order Assigned",
      body: `"${firstProductName}" – Order #${shortOrderId} ready.`,
      type: "order",
      orderId: orderRef.id,
      messageId,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    });

    return { success: true, orderId: orderRef.id };
  } catch (error) {
    logger.error("createOrder failed:", error);
    throw new HttpsError("internal", `Failed: ${error.message}`);
  }
});

/* -------------------------------------------------------
   Order Status Update
---------------------------------------------------------- */
export const notifyOrderUpdated = onDocumentUpdated("orders/{orderId}", async (event) => {
  const newData = event.data.after.data();
  const oldData = event.data.before.data();
  if (newData.deliveryStatus === oldData.deliveryStatus) return;

  const userId = newData.userId;
  if (!userId) return;

  const items = newData.items || [];
  const firstProductName = items[0]?.name || "your item";
  const shortOrderId = event.params.orderId.substring(0, 8);
  const messageId = `status_${event.params.orderId}_${newData.deliveryStatus}`;

  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) return;

  const fcmToken = userDoc.data().fcmToken;

  let title = "Order Update";
  let body = `"${firstProductName}" (Order #${shortOrderId}) is now "${newData.deliveryStatus}".`;

  switch ((newData.deliveryStatus || "").toLowerCase()) {
    case "shipped": title = "On the way!"; body = `"${firstProductName}" is out for delivery (Order #${shortOrderId}).`; break;
    case "delivered": title = "Delivered"; body = `"${firstProductName}" has been delivered! (Order #${shortOrderId})`; break;
    case "cancelled": case "canceled": title = "Order Cancelled"; body = `Order #${shortOrderId} cancelled.`; break;
    case "processing": title = "Order Processing"; body = `"${firstProductName}" is being prepared (Order #${shortOrderId}).`; break;
  }

  await db.collection("users").doc(userId).collection("inAppNotifications").add({
    title, body, type: "order", orderId: event.params.orderId,
    deliveryStatus: newData.deliveryStatus, messageId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(), read: false,
  });

  if (fcmToken) {
    await safeSendFCM({
      token: fcmToken,
      notification: { title, body },
      data: { type: "order", orderId: event.params.orderId, deliveryStatus: newData.deliveryStatus, messageId, click_action: "FLUTTER_NOTIFICATION_CLICK" },
      android: { priority: "high", notification: { channelId: "daligas_channel", sound: "default" } },
    }, userId);
  }
});

/* -------------------------------------------------------
   New Chat Message → Push Notification + In-App (FINAL VERSION)
---------------------------------------------------------- */
export const notifyOnNewMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const messageData = event.data.data();
    const chatId = event.params.chatId;
    const messageId = event.params.messageId;

    const text = messageData.text?.trim();
    const senderId = messageData.senderId;
    const senderRole = messageData.senderRole;
    const seen = messageData.seen === true;

    logger.info("=== NEW MESSAGE DETECTED ===", {
      chatId,
      messageId,
      text,
      senderId,
      senderRole,
      seen,
    });

    if (!text || !senderId || !senderRole || seen) {
      logger.warn("Invalid or seen message - skipping");
      return;
    }

    // === READ CHAT DOCUMENT DIRECTLY (no metadata/info) ===
    const chatDoc = await db.collection("chats").doc(chatId).get();
    if (!chatDoc.exists) {
      logger.error("Chat document not found:", chatId);
      return;
    }

    const chatData = chatDoc.data();
    logger.info("Chat document data:", chatData);

    const customerId = chatData.customerId;
    const employeeId = chatData.employeeId;
    const orderId = chatData.orderId || null;

    if (!customerId || !employeeId) {
      logger.error("Missing customerId or employeeId in chat doc", { chatData });
      return;
    }

    const isFromCustomer = senderRole === "customer";
    const recipientId = isFromCustomer ? employeeId : customerId;
    const recipientCollection = isFromCustomer ? "employees" : "users";

    logger.info("Recipient resolved", { recipientId, recipientCollection, isFromCustomer });

    // === GET SENDER NAME (for title) ===
    let senderName = "User";

    if (senderRole === "customer") {
      const customerSnap = await db.collection("users").doc(senderId).get();
      if (customerSnap.exists) {
        senderName = customerSnap.data()?.fullName || "Customer";
      } else {
        senderName = "Customer";
      }
    } else if (senderRole === "employee") {
      const empSnap = await db.collection("employees").doc(senderId).get();
      if (empSnap.exists) {
        senderName = empSnap.data()?.name || "Driver";
      } else {
        senderName = "Driver";
      }
    }

    const shortMsg = text.length > 60 ? text.substring(0, 57) + "..." : text;
    const title = `New Message from ${senderName}`;
    const body = `"${shortMsg}"`;
    const fcmMessageId = `msg_${chatId}_${messageId}`;

    // === SAVE IN-APP NOTIFICATION ===
    await db
      .collection(recipientCollection)
      .doc(recipientId)
      .collection("inAppNotifications")
      .add({
        title,
        body,
        type: "message",
        chatId,
        orderId,
        messageId: fcmMessageId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      });

    logger.info("In-app notification saved for", recipientId);

    // === FETCH RECIPIENT FCM TOKEN ===
    const recipientDoc = await db.collection(recipientCollection).doc(recipientId).get();
    if (!recipientDoc.exists) {
      logger.error("Recipient document not found", { recipientId });
      return;
    }

    const fcmToken = recipientDoc.data()?.fcmToken;

    // === SEND PUSH NOTIFICATION ===
    if (fcmToken) {
      const message = {
        token: fcmToken,
        notification: { title, body },
        data: {
          type: "message",
          chatId: String(chatId),
          orderId: orderId || "",
          title: title, // ← for Flutter click handler
          messageId: fcmMessageId,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "daligas_channel",
            sound: "default",
          },
        },
      };

      const result = await safeSendFCM(message, recipientId);
      logger.info("FCM send result:", result);
    } else {
      logger.warn("No FCM token for recipient", { recipientId, recipientCollection });
    }

    logger.info("=== CHAT NOTIFICATION SUCCESS ===");
  }
);

/* -------------------------------------------------------
   LPG Price Sync
---------------------------------------------------------- */
export const checkDOEArticles = onSchedule(
  { schedule: "0 8 * * 0", timeZone: "Asia/Manila" },
  async () => {
    try {
      const oimbUrl = "https://doe.gov.ph/site/oimb";
      const { data } = await axios.get(oimbUrl);
      const $ = cheerio.load(data);

      let latestPdfUrl = "", latestMonth = "";
      for (const art of $("article").toArray()) {
        const title = $(art).find("h2").text();
        if (/price monitoring.*lpg/i.test(title)) {
          const link = $(art).find("a").attr("href");
          if (link?.endsWith(".pdf")) {
            latestPdfUrl = link.startsWith("http") ? link : `https://doe.gov.ph${link}`;
            latestMonth = title.match(/for the month of (\w+ \d{4})/i)?.[1] || "";
            break;
          }
        }
      }

      if (!latestPdfUrl) return logger.info("No new LPG PDF.");

      const docRef = db.collection("doe_latest").doc("lpg");
      const doc = await docRef.get();
      if (doc.exists && doc.data()?.pdfUrl === latestPdfUrl) return logger.info("Already processed.");

      const pdfData = await pdfParse((await axios.get(latestPdfUrl, { responseType: "arraybuffer" })).data);
      const match = pdfData.text.match(/range from ₱(\d+)\.?\d* to ₱(\d+)\.?\d*/i);
      if (!match) return logger.warn("Could not parse price.");

      const [_, priceMin, priceMax] = match.map(Number);
      await docRef.set({
        pdfUrl: latestPdfUrl, month: latestMonth,
        pricePerKgMin: priceMin, pricePerKgMax: priceMax,
        lastChecked: admin.firestore.FieldValue.serverTimestamp(),
      });

      const snapshot = await db.collection("products").where("srpLinked", "==", true).get();
      const batch = db.batch();
      snapshot.forEach(doc => batch.update(doc.ref, { priceMin, priceMax, lastDOEUpdate: admin.firestore.FieldValue.serverTimestamp() }));
      await batch.commit();

      logger.log(`Updated ${snapshot.size} products with DOE LPG prices.`);
    } catch (error) {
      logger.error("checkDOEArticles error:", error);
    }
  }
);

/* -------------------------------------------------------
   PLACES AUTOCOMPLETE PROXY
---------------------------------------------------------- */
export const placesAutocomplete = https.onRequest((req, res) => {
  cors(req, res, async () => {
    const { input } = req.query;
    if (!input || input.toString().trim() === "") {
      return res.status(400).json({ error: "Missing or empty `input`" });
    }

    const API_KEY = defineString("GOOGLE_PLACES_KEY").value();
    if (!API_KEY) {
      logger.error("Google Places API key missing. Run: firebase functions:config:set google.places_key=\"YOUR_KEY\"");
      return res.status(500).json({ error: "Server misconfigured" });
    }

    try {
      const googleUrl = "https://maps.googleapis.com/maps/api/place/autocomplete/json";
      const params = new URLSearchParams({
        input: input.toString(),
        key: API_KEY,
        language: "en",
        components: "country:ph",
      });

      const googleResp = await fetch(`${googleUrl}?${params}`);
      const data = await googleResp.json();

      res.status(googleResp.status).json(data);
    } catch (err) {
      logger.error("placesAutocomplete error:", err);
      res.status(500).json({ error: "Failed to contact Google" });
    }
  });
});

/* -------------------------------------------------------
   PLACE DETAILS PROXY
---------------------------------------------------------- */
export const placeDetails = https.onRequest((req, res) => {
  cors(req, res, async () => {
    const { placeid } = req.query;
    if (!placeid || placeid.toString().trim() === "") {
      return res.status(400).json({ error: "Missing or empty `placeid`" });
    }

    const API_KEY = defineString("GOOGLE_PLACES_KEY").value();
    if (!API_KEY) {
      logger.error("Google Places API key missing");
      return res.status(500).json({ error: "Server misconfigured" });
    }

    try {
      const googleUrl = "https://maps.googleapis.com/maps/api/place/details/json";
      const params = new URLSearchParams({
        place_id: placeid.toString(),
        key: API_KEY,
        language: "en",
      });

      const googleResp = await fetch(`${googleUrl}?${params}`);
      const data = await googleResp.json();

      res.status(googleResp.status).json(data);
    } catch (err) {
      logger.error("placeDetails error:", err);
      res.status(500).json({ error: "Failed to contact Google" });
    }
  });
});