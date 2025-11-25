// NEW FUNCTIONS // 

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

const REGION = "asia-southeast1";

const adminApp = initializeApp();
const db = getFirestore(adminApp, "daligas");
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
   Helper: assign employee (same logic as createOrder)
---------------------------------------------------------- */
async function assignEmployee() {
  const employeesSnap = await db.collection("employees").get();
  if (employeesSnap.empty) return null;

  let chosen = null, min = Infinity;
  for (const doc of employeesSnap.docs) {
    const count = await db.collection("orders")
      .where("employeeId", "==", doc.id)
      .where("deliveryStatus", "in", ["Processing", "Shipped"])
      .get()
      .then(s => s.size);
    if (count < min) { min = count; chosen = doc.id; }
  }
  return chosen;
}

/* -------------------------------------------------------
   Generate Custom Token
---------------------------------------------------------- */
export const getCustomToken = onCall({ region: REGION, database: "daligas" }, async (request) => {
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
export const registerFcmToken = onCall({ region: REGION, database: "daligas" }, async (request) => {
  const { userId, fcmToken } = request.data;
  if (!userId || !fcmToken) throw new HttpsError("invalid-argument", "userId and fcmToken required.");

  await db.collection("users").doc(userId).update({ fcmToken });
  return { success: true, message: "FCM token registered." };
});

/* -------------------------------------------------------
   Manual Notification Sender (Admin)
---------------------------------------------------------- */
export const sendNotification = onCall({ region: REGION, database: "daligas" }, async (request) => {
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
   createOrder — COD & GCash Flow
---------------------------------------------------------- */
export const createOrder = onCall({ region: REGION, database: "daligas"}, async (request) => {
  const { userId, items, paymentMethod, deliveryAddress } = request.data;
  if (!userId || !items?.length) throw new HttpsError("invalid-argument", "Missing details.");
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");

  const normalizedMethod = (paymentMethod || 'cod').toLowerCase();
  const isCOD = normalizedMethod === 'cod';

  try {
    const chosenEmployeeId = await assignEmployee();
    if (!chosenEmployeeId) throw new HttpsError("failed-precondition", "No employees available.");

    const total = items.reduce((sum, i) => sum + i.price * i.quantity, 0);
    const orderRef = db.collection("orders").doc();

    await orderRef.set({
      orderId: orderRef.id,
      userId,
      employeeId: chosenEmployeeId,
      items,
      total,
      paymentMethod: normalizedMethod,
      paymentStatus: isCOD ? 'Pending' : 'Paid',
      deliveryStatus: "Processing",
      deliveryAddress,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await Promise.all(items.map(async (item) => {
      const productRef = db.collection("products").doc(item.productId);
      return db.runTransaction(async (t) => {
        const doc = await t.get(productRef);
        if (!doc.exists) return;
        const currentStock = doc.data()?.stock || 0;
        const newStock = Math.max(currentStock - item.quantity, 0);
        t.update(productRef, { stock: newStock });
      });
    }));

    const firstProductName = items[0]?.name || "your item";
    const shortOrderId = orderRef.id.substring(0, 8);
    const messageId = `order_${orderRef.id}`;

    const chatId = `${userId}_${chosenEmployeeId}_${orderRef.id}`;
    await db.collection("chats").doc(chatId).set({
      customerId: userId,
      employeeId: chosenEmployeeId,
      orderId: orderRef.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      deletedByCustomer: false,
      deletedByEmployee: false,
    }, { merge: true });

    await db.collection("chats").doc(chatId).collection("metadata").doc("info").set({
      userId, employeeId: chosenEmployeeId, orderId: orderRef.id,
    });

    const userDoc = await db.collection("users").doc(userId).get();
    const userFcmToken = userDoc.data()?.fcmToken;
    if (userFcmToken) {
      await safeSendFCM({
        token: userFcmToken,
        notification: {
          title: "Order Placed!",
          body: `"${firstProductName}" • Order #${shortOrderId} • ${isCOD ? 'COD' : 'Paid via GCash'}`
        },
        data: { type: "order", orderId: orderRef.id, messageId, click_action: "FLUTTER_NOTIFICATION_CLICK" },
        android: { priority: "high", notification: { channelId: "daligas_channel" } },
      }, userId);
    }

    const empDoc = await db.collection("employees").doc(chosenEmployeeId).get();
    const empFcmToken = empDoc.data()?.fcmToken;
    if (empFcmToken) {
      await safeSendFCM({
        token: empFcmToken,
        notification: {
          title: "New Order Assigned",
          body: `"${firstProductName}" – #${shortOrderId} (${isCOD ? 'COD' : 'GCash'})`
        },
        data: { type: "order", orderId: orderRef.id, messageId, click_action: "FLUTTER_NOTIFICATION_CLICK" },
        android: { priority: "high", notification: { channelId: "daligas_channel" } },
      }, chosenEmployeeId);
    }

    return { success: true, orderId: orderRef.id };
  } catch (error) {
    logger.error("createOrder failed:", error);
    throw new HttpsError("internal", `Failed: ${error.message}`);
  }
});

/* -------------------------------------------------------
   createPaymongoPayment – ERROR-PROOF FOR LIVE
---------------------------------------------------------- */
export const createPaymongoPayment = onCall(
  { region: REGION, secrets: ["PAYMONGO_SECRET_KEY"], database: "daligas" },
  async (request) => {
    // Early validation with clear errors
    const { userId, items, deliveryAddress } = request.data;
    if (!userId || !items?.length || !deliveryAddress) {
      throw new HttpsError("invalid-argument", "Missing required fields: userId, items, or deliveryAddress.");
    }
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    let total = 0;
    try {
      total = items.reduce((sum, i) => sum + Number(i.price || 0) * Number(i.quantity || 0), 0);
    } catch (e) {
      throw new HttpsError("invalid-argument", `Invalid items data: ${e.message}. Ensure price/quantity are numbers.`);
    }

    const amountInCentavos = Math.round(total * 100);
    if (amountInCentavos < 100) {
      throw new HttpsError("invalid-argument", "Order total must be at least ₱1.00.");
    }

    try {
      const PAYMONGO_SECRET_KEY = defineSecret("PAYMONGO_SECRET_KEY").value();
      if (!PAYMONGO_SECRET_KEY || !PAYMONGO_SECRET_KEY.startsWith('sk_live_')) {
        throw new HttpsError("internal", "PayMongo configuration error. Contact support.");
      }

      // Assign employee safely
      let chosenEmployeeId = null;
      try {
        chosenEmployeeId = await assignEmployee();
        if (!chosenEmployeeId) throw new Error("No employees available.");
      } catch (e) {
        logger.warn(`Employee assignment failed: ${e.message}. Proceeding without.`);
      }

      const orderRef = db.collection("orders").doc();
      const orderId = orderRef.id;

      // Safe order creation (no stock deduction)
      await orderRef.set({
        orderId,
        userId,
        employeeId: chosenEmployeeId,
        items,
        total,
        paymentMethod: "gcash",
        paymentStatus: "Awaiting Payment",
        deliveryStatus: "Pending",
        deliveryAddress,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        paidVia: "PayMongo",
        paymongoSourceId: null,
        checkoutUrl: null,
        expiresAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.info(`Order ${orderId} created successfully. Total: ₱${total.toFixed(2)}`);

      // PayMongo API call – REPLACED WITH YOUR EXACT VERSION
      const authHeader = `Basic ${Buffer.from(`${PAYMONGO_SECRET_KEY}:`).toString("base64")}`;
      let sourceResponse;
      try {
        sourceResponse = await axios({
          method: "post",
          url: "https://api.paymongo.com/v1/sources",
          headers: {
            "Content-Type": "application/json",
            "Authorization": authHeader,
            "Accept": "application/json",
          },
          data: {
            data: {
              attributes: {
                amount: amountInCentavos,
                currency: "PHP",
                type: "gcash",
                redirect: {
                  success: `https://daligas.app/success?orderId=${orderId}`,
                  failed: `https://daligas.app/failed?orderId=${orderId}`
                }
              }
            }
          }
        });
      } catch (apiError) {
        const errorMsg = apiError.response?.data?.errors?.[0]?.detail || apiError.response?.data?.message || apiError.message || "Unknown PayMongo error";
        logger.error(`PayMongo API failed for order ${orderId}: ${errorMsg}`, { error: apiError.response?.data });
        await orderRef.delete();
        throw new HttpsError("internal", `Payment setup failed: ${errorMsg}. Please try again.`);
      }

      const source = sourceResponse.data.data;
      if (!source?.attributes?.redirect?.checkout_url) {
        await orderRef.delete();
        throw new HttpsError("internal", "Invalid PayMongo response. Please try again.");
      }

      await orderRef.update({
        paymongoSourceId: source.id,
        checkoutUrl: source.attributes.redirect.checkout_url,
        expiresAt: new Date(Date.now() + 60 * 60 * 1000),
      });

      // Optional FCM notification
      try {
        const userDoc = await db.collection("users").doc(userId).get();
        const fcmToken = userDoc.data()?.fcmToken;
        const shortId = orderId.substring(0, 8);
        if (fcmToken) {
          await safeSendFCM({
            token: fcmToken,
            notification: { title: "GCash Payment Required", body: `Order #${shortId} • ₱${total.toFixed(2)} • Complete in GCash` },
            data: { type: "order", orderId, click_action: "FLUTTER_NOTIFICATION_CLICK" },
          }, userId);
        }
      } catch (fcmError) {
        logger.warn(`FCM send failed for user ${userId}: ${fcmError.message}`);
      }

      logger.info(`PayMongo source created for order ${orderId}. Redirect ready.`);
      return { success: true, redirectUrl: source.attributes.redirect.checkout_url, orderId };

    } catch (error) {
      const safeError = error instanceof HttpsError ? error : new HttpsError("internal", error.message || "Unknown error");
      logger.error(`createPaymongoPayment error: ${safeError.message}`, {
        userId,
        total,
        itemsCount: items.length,
        errorCode: safeError.code,
        stack: error.stack?.substring(0, 1000),
      });
      throw safeError;
    }
  }
);

/* -------------------------------------------------------
   PayMongo Webhook – NOW THE SINGLE SOURCE OF TRUTH
   Handles: SUCCESS, FAILED, EXPIRED
---------------------------------------------------------- */
export const paymongoWebhook = https.onRequest(
  { region: REGION, secrets: ["PAYMONGO_WEBHOOK_SECRET"], database: "daligas" },
  async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

    const PAYMONGO_WEBHOOK_SECRET = defineSecret("PAYMONGO_WEBHOOK_SECRET").value();
    const signature = req.headers["paymongo-signature"];
    if (!signature || !PAYMONGO_WEBHOOK_SECRET) return res.status(401).send("Unauthorized");

    const [tPart, v1Part] = signature.split(",");
    const timestamp = tPart.split("=")[1];
    const providedSig = v1Part.split("=")[1];
    const payload = JSON.stringify(req.body);
    const expectedSig = require("crypto")
      .createHmac("sha256", PAYMONGO_WEBHOOK_SECRET)
      .update(`${timestamp}.${payload}`)
      .digest("hex");

    if (expectedSig !== providedSig) {
      logger.warn("Invalid webhook signature");
      return res.status(401).send("Invalid signature");
    }

    const event = req.body.data;
    const eventType = event.attributes.type;

    // 1. SUCCESS – source.chargeable
    if (eventType === "source.chargeable") {
      const source = event.attributes.data;
      if (source.attributes.type !== "gcash") return res.json({ received: true });

      const match = source.attributes.redirect.success.match(/orderId=([^&]+)/);
      if (!match) return res.json({ received: true });
      const orderId = match[1];

      const orderRef = db.collection("orders").doc(orderId);
      const orderDoc = await orderRef.get();

      if (!orderDoc.exists || orderDoc.data()?.paymentStatus !== "Awaiting Payment") {
        logger.info("Order already processed or invalid:", orderId);
        return res.json({ received: true });
      }

      const orderData = orderDoc.data();

      // DEDUCT STOCK ONLY NOW – THIS IS THE ONLY PLACE
      await Promise.all(
        orderData.items.map(async (item) => {
          const productId = item.productId || item.id;
          if (!productId) return;
          const productRef = db.collection("products").doc(productId);
          await db.runTransaction(async (t) => {
            const doc = await t.get(productRef);
            if (!doc.exists) return;
            const currentStock = doc.data()?.stock || 0;
            if (currentStock < (item.quantity || 1)) {
              throw new Error(`Insufficient stock for ${productId}`);
            }
            t.update(productRef, { stock: currentStock - (item.quantity || 1) });
          });
        })
      );

      await orderRef.update({
        paymentStatus: "Paid",
        deliveryStatus: "Processing",
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Send notification
      const userDoc = await db.collection("users").doc(orderData.userId).get();
      const fcmToken = userDoc.data()?.fcmToken;
      if (fcmToken) {
        await safeSendFCM({
          token: fcmToken,
          notification: {
            title: "Payment Confirmed!",
            body: `Your GCash payment for Order #${orderId.substring(0, 8)} was successful!`,
          },
          data: { type: "order", orderId },
        }, orderData.userId);
      }

      logger.log(`GCash order ${orderId} PAID & stock deducted`);
    }

    // 2. FAILED / EXPIRED – cancel order + return stock (if any was held)
    else if (eventType === "source.failed" || eventType === "source.expired") {
      const source = event.attributes.data;
      const orderId = source.attributes.redirect?.failed?.match(/orderId=([^&]+)/)?.[1] ||
                     source.attributes.redirect?.success?.match(/orderId=([^&]+)/)?.[1];

      if (!orderId) return res.json({ received: true });

      const orderRef = db.collection("orders").doc(orderId);
      const orderDoc = await orderRef.get();
      if (!orderDoc.exists) return res.json({ received: true });

      await orderRef.update({
        paymentStatus: "Failed",
        deliveryStatus: "Cancelled",
        cancelReason: eventType === "source.expired" ? "Payment expired" : "Payment failed",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.log(`GCash order ${orderId} cancelled: ${eventType}`);
    }

    res.json({ received: true });
  }
);

/* -------------------------------------------------------
   Order Status Update
---------------------------------------------------------- */
export const notifyOrderUpdated = onDocumentUpdated(
  { document: "orders/{orderId}", region: REGION, database: "daligas" },
  async (event) => {
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
  }
);

/* -------------------------------------------------------
   New Chat Message → Push Notification + In-App
---------------------------------------------------------- */
export const notifyOnNewMessage = onDocumentCreated(
  { document: "chats/{chatId}/messages/{messageId}", region: REGION, database: "daligas"},
  async (event) => {
    const messageData = event.data.data();
    const chatId = event.params.chatId;
    const messageId = event.params.messageId;

    const text = messageData.text?.trim();
    const senderId = messageData.senderId;
    const senderRole = messageData.senderRole;
    const seen = messageData.seen === true;

    if (!text || !senderId || !senderRole || seen) return;

    const chatDoc = await db.collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return;

    const chatData = chatDoc.data();
    const customerId = chatData.customerId;
    const employeeId = chatData.employeeId;
    const orderId = chatData.orderId || null;

    if (!customerId || !employeeId) return;

    const isFromCustomer = senderRole === "customer";
    const recipientId = isFromCustomer ? employeeId : customerId;
    const recipientCollection = isFromCustomer ? "employees" : "users";

    let senderName = "User";
    if (senderRole === "customer") {
      const snap = await db.collection("users").doc(senderId).get();
      senderName = snap.exists ? snap.data()?.fullName || "Customer" : "Customer";
    } else if (senderRole === "employee") {
      const snap = await db.collection("employees").doc(senderId).get();
      senderName = snap.exists ? snap.data()?.name || "Driver" : "Driver";
    }

    const shortMsg = text.length > 60 ? text.substring(0, 57) + "..." : text;
    const title = `New Message from ${senderName}`;
    const body = `"${shortMsg}"`;
    const fcmMessageId = `msg_${chatId}_${messageId}`;

    await db.collection(recipientCollection)
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

    const recipientDoc = await db.collection(recipientCollection).doc(recipientId).get();
    if (!recipientDoc.exists) return;

    const fcmToken = recipientDoc.data()?.fcmToken;
    if (fcmToken) {
      const message = {
        token: fcmToken,
        notification: { title, body },
        data: {
          type: "message",
          chatId: String(chatId),
          orderId: orderId || "",
          title: title,
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

      await safeSendFCM(message, recipientId);
    }
  }
);

/* -------------------------------------------------------
   LPG Price Sync
---------------------------------------------------------- */
export const checkDOEArticles = onSchedule(
  { schedule: "0 8 * * 0", timeZone: "Asia/Manila", region: REGION, database: "daligas" },
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
export const placesAutocomplete = https.onRequest(
  { region: REGION, database: "daligas" },
  (req, res) => {
    cors(req, res, async () => {
      const { input } = req.query;
      if (!input || input.toString().trim() === "") {
        return res.status(400).json({ error: "Missing or empty `input`" });
      }

      const API_KEY = defineString("GOOGLE_PLACES_KEY").value();
      if (!API_KEY) {
        logger.error("Google Places API key missing.");
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
  }
);

/* -------------------------------------------------------
   PLACE DETAILS PROXY
---------------------------------------------------------- */
export const placeDetails = https.onRequest(
  { region: REGION, database: "daligas" },
  (req, res) => {
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
  }
);

// DEPLOYED TO asia-southeast1 — 2025-11-19