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
   createOrder — COD & GCash Flow (Now supports Manual Orders)
---------------------------------------------------------- */
export const createOrder = onCall({ region: REGION, database: "daligas" }, async (request) => {
  const {
    userId,                    // Optional for manual orders
    items,
    paymentMethod,
    deliveryAddress,
    customerName,              // ← NEW: for manual orders
    customerPhone,             // ← NEW: optional
    isManualOrder = false      // ← NEW: flag to detect admin manual order
  } = request.data;

  // Validation
  if (!items?.length) throw new HttpsError("invalid-argument", "Missing items.");
  if (!deliveryAddress || deliveryAddress.trim() === "") {
    throw new HttpsError("invalid-argument", "Delivery address is required.");
  }

  const normalizedMethod = (paymentMethod || 'cod').toLowerCase();
  const isCOD = normalizedMethod === 'cod';

  let finalUserId = userId;
  let finalCustomerName = customerName?.trim() || "Guest Customer";
  let finalCustomerPhone = customerPhone?.trim() || null;

  try {
    // ——— CASE 1: Regular User Order ———
    if (!isManualOrder) {
      if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
      if (!userId) throw new HttpsError("invalid-argument", "userId is required for regular orders.");
      finalUserId = request.auth.uid;

      // Fetch user's name if not provided
      if (!customerName) {
        const userDoc = await db.collection("users").doc(finalUserId).get();
        if (userDoc.exists) {
          finalCustomerName = userDoc.data()?.fullName || "Unknown User";
        }
      }
    }
    // ——— CASE 2: Manual Order by Admin ———
    else {
      // Allow unauthenticated calls (admin panel uses service account)
      // No userId required → we don't save it
      finalUserId = null;

      if (!customerName || customerName.trim() === "") {
        throw new HttpsError("invalid-argument", "customerName is required for manual orders.");
      }
    }

    const chosenEmployeeId = await assignEmployee();
    if (!chosenEmployeeId) throw new HttpsError("failed-precondition", "No employees available.");

    const total = items.reduce((sum, i) => sum + i.price * i.quantity, 0);
    const orderRef = db.collection("orders").doc();

    // Process items: ensure imageUrl is preserved
    const processedItems = items.map(item => ({
      productId: item.productId,
      name: item.name,
      price: item.price,
      quantity: item.quantity,
      imageUrl: item.imageUrl || "",   // ← Preserve image URL
    }));

    await orderRef.set({
      orderId: orderRef.id,
      userId: finalUserId,                    // ← null for manual orders
      employeeId: chosenEmployeeId,
      items: processedItems,
      total: Number(total.toFixed(2)),
      paymentMethod: normalizedMethod,
      paymentStatus: isCOD ? 'Pending' : 'Paid',
      deliveryStatus: "Processing",
      deliveryAddress,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),

      // ——— NEW FIELDS (safe for all orders) ———
      customerName: finalCustomerName,
      customerPhone: finalCustomerPhone || null,
      isManualOrder: !!isManualOrder,         // ← Flag for filtering/reporting
    });

    // Reduce stock safely — SKIP deleted or invalid products
await Promise.all(
  items.map(async (item) => {
    const productId = item.productId || item.id;
    
    // Critical: skip if productId is missing, null, undefined, or empty
    if (!productId || typeof productId !== "string" || productId.trim() === "") {
      logger.warn("Skipping stock deduction - invalid productId:", item);
      return;
    }

    const productRef = db.collection("products").doc(productId);

    try {
      await db.runTransaction(async (t) => {
        const doc = await t.get(productRef);
        if (!doc.exists) {
          logger.info(`Product ${productId} no longer exists — skipping stock deduction`);
          return;
        }
        const currentStock = doc.data()?.stock || 0;
        const deductQty = Number(item.quantity) || 1;
        const newStock = Math.max(currentStock - deductQty, 0);
        t.update(productRef, { stock: newStock });
      });
    } catch (err) {
      logger.warn(`Failed to deduct stock for product ${productId}:`, err.message);
      // Don't crash the whole order — just log and continue
    }
  })
);

    const firstProductName = processedItems[0]?.name || "your item";
    const shortOrderId = orderRef.id.substring(0, 8);
    const messageId = `order_${orderRef.id}`;

    // Create chat only if there's a real user (skip for manual orders if no userId)
    if (finalUserId) {
      const chatId = `${finalUserId}_${chosenEmployeeId}_${orderRef.id}`;
      await db.collection("chats").doc(chatId).set({
        customerId: finalUserId,
        employeeId: chosenEmployeeId,
        orderId: orderRef.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedByCustomer: false,
        deletedByEmployee: false,
      }, { merge: true });

      await db.collection("chats").doc(chatId).collection("metadata").doc("info").set({
        userId: finalUserId,
        employeeId: chosenEmployeeId,
        orderId: orderRef.id,
      });
    }

    // Send FCM to customer (only if userId exists and has token)
    if (finalUserId) {
      const userDoc = await db.collection("users").doc(finalUserId).get();
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
        }, finalUserId);
      }
    }

    // Always notify the assigned employee
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
   createPaymongoPayment — GCash Flow
---------------------------------------------------------- */
export const createPaymongoPayment = onCall(
  { region: REGION, secrets: ["PAYMONGO_SECRET_KEY"], database: "daligas" },
  async (request) => {
    const { userId, items, deliveryAddress } = request.data;

    if (!userId || !items?.length || !deliveryAddress)
      throw new HttpsError("invalid-argument", "Missing required fields.");

    if (!request.auth)
      throw new HttpsError("unauthenticated", "Login required.");

    const PAYMONGO_SECRET_KEY = defineSecret("PAYMONGO_SECRET_KEY").value();
    const total = items.reduce((sum, i) => sum + Number(i.price) * Number(i.quantity), 0);
    const amountInCentavos = Math.round(total * 100);

    if (amountInCentavos < 100)
      throw new HttpsError("invalid-argument", "Order total must be at least ₱1.00");

    try {
      const chosenEmployeeId = await assignEmployee();
      if (!chosenEmployeeId) throw new HttpsError("failed-precondition", "No employees available.");

      const orderRef = db.collection("orders").doc();
      const orderId = orderRef.id;

      await orderRef.set({
        orderId: orderRef.id,
        userId,
        employeeId: chosenEmployeeId,
        items,
        total,
        paymentMethod: "gcash",
        paymentStatus: "Pending",
        deliveryStatus: "Processing",
        deliveryAddress,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        paidVia: "PayMongo",
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

      const authHeader = `Basic ${Buffer.from(`${PAYMONGO_SECRET_KEY}:`).toString("base64")}`;

      const sourceResponse = await axios({
        method: "post",
        url: "https://api.paymongo.com/v1/sources",
        headers: {
          "Content-Type": "application/json",
          Authorization: authHeader,
        },
        data: {
          data: {
            attributes: {
              amount: amountInCentavos,
              type: "gcash",
              currency: "PHP",
              redirect: {
                success: `https://daligas.app/success?orderId=${orderId}`,
                failed: `https://daligas.app/failed?orderId=${orderId}`,
              },
            },
          },
        },
      });

      const source = sourceResponse.data.data;

      await orderRef.update({
        paymongoSourceId: source.id,
        checkoutUrl: source.attributes.redirect.checkout_url,
      });

      const userDoc = await db.collection("users").doc(userId).get();
      const fcmToken = userDoc.data()?.fcmToken;
      const shortId = orderId.substring(0, 8);

      if (fcmToken) {
        await safeSendFCM({
          token: fcmToken,
          notification: {
            title: "GCash Payment Required",
            body: `Order #${shortId} • ₱${total.toFixed(2)} • Complete in GCash`,
          },
          data: { type: "order", orderId, click_action: "FLUTTER_NOTIFICATION_CLICK" },
        }, userId);
      }

      return {
        success: true,
        redirectUrl: source.attributes.redirect.checkout_url,
        orderId: orderId,
      };
    } catch (error) {
      logger.error("createPaymongoPayment failed:", error.response?.data || error);
      throw new HttpsError("internal", "GCash payment setup failed. Please try again.");
    }
  }
);

/* -------------------------------------------------------
   PayMongo Webhook – Confirm GCash Payment
---------------------------------------------------------- */
export const paymongoWebhook = https.onRequest(
  { region: REGION, secrets: ["PAYMONGO_WEBHOOK_SECRET"], database: "daligas" },
  async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

    const PAYMONGO_WEBHOOK_SECRET = defineSecret("PAYMONGO_WEBHOOK_SECRET").value();
    const signature = req.headers["paymongo-signature"];

    if (!signature || !PAYMONGO_WEBHOOK_SECRET) {
      return res.status(401).send("Unauthorized");
    }

    const [tPart, v1Part] = signature.split(",");
    const timestamp = tPart.split("=")[1];
    const providedSig = v1Part.split("=")[1];
    const payload = JSON.stringify(req.body);
    const expectedSig = require("crypto")
      .createHmac("sha256ॉ", PAYMONGO_WEBHOOK_SECRET)
      .update(`${timestamp}.${payload}`)
      .digest("hex");

    if (expectedSig !== providedSig) {
      logger.warn("Invalid webhook signature");
      return res.status(401).send("Invalid signature");
    }

    const event = req.body.data;

    if (event.attributes.type === 'source.chargeable') {
      const source = event.attributes.data;
      if (source.attributes.type !== 'gcash') return res.json({ received: true });

      const match = source.attributes.redirect.success.match(/orderId=([^&]+)/);
      if (!match) {
        logger.warn("No orderId in redirect URL");
        return res.json({ received: true });
      }
      const orderId = match[1];

      const orderDoc = await db.collection('orders').doc(orderId).get();

      if (!orderDoc.exists || orderDoc.data()?.paymentStatus !== 'Pending') {
        logger.info("Order not pending or already processed:", orderId);
        return res.json({ received: true });
      }

      const orderData = orderDoc.data();

      await orderDoc.ref.update({
        paymentStatus: 'Paid',
        deliveryStatus: 'Processing',
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        isPendingGcash: false,
      });

      await Promise.all(
        orderData.items.map(async (item) => {
          const productId = item.productId || item.id;
          if (!productId) return;

          const productRef = db.collection("products").doc(productId);
          await db.runTransaction(async (t) => {
            const doc = await t.get(productRef);
            if (!doc.exists) return;
            const currentStock = doc.data()?.stock || 0;
            const newStock = Math.max(currentStock - (item.quantity || 1), 0);
            t.update(productRef, { stock: newStock });
          });
        })
      );

      const employeeId = await assignEmployee();
      if (employeeId) {
        await orderDoc.ref.update({ employeeId });
      }

      const shortId = orderId.substring(0, 8);
      const userDoc = await db.collection("users").doc(orderData.userId).get();
      const fcmToken = userDoc.data()?.fcmToken;

      if (fcmToken) {
        await safeSendFCM({
          token: fcmToken,
          notification: {
            title: "Payment Confirmed!",
            body: `Your GCash payment for Order #${shortId} was successful!`,
          },
          data: { type: "order", orderId },
        }, orderData.userId);
      }

      logger.log(`Pending GCash order ${orderId} finalized successfully`);
    }

    res.json({ received: true });
  }
);

// -------------------------------------------------------
// Auto-cancel abandoned GCash orders after 24 hours
// -------------------------------------------------------
export const cleanupAbandonedGcashOrders = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Asia/Manila",        // Good for PH users
    region: REGION,
    database: "daligas"
  },
  async (event) => {
    const cutoff = getFirestore().Timestamp.fromDate(
  new Date(Date.now() - 24 * 60 * 60 * 1000)
);

    const abandonedOrdersSnap = await db
      .collection("orders")
      .where("paymentMethod", "==", "gcash")
      .where("paymentStatus", "==", "Pending")
      .where("createdAt", "<", cutoff)
      .get();

    if (abandonedOrdersSnap.empty) {
      logger.info("No abandoned GCash orders found.");
      return null;
    }

    const batch = db.batch();
    let count = 0;

    for (const doc of abandonedOrdersSnap.docs) {
      count++;
      const orderData = doc.data();

      // Cancel order
      batch.update(doc.ref, {
        paymentStatus: "Expired",
        deliveryStatus: "Cancelled",
        cancelledReason: "GCash payment not completed within 24 hours",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Restock items
      for (const item of orderData.items || []) {
        const productId = item.productId || item.id;
        if (productId && item.quantity > 0) {
          const productRef = db.collection("products").doc(productId);
          batch.update(productRef, {
            stock: admin.firestore.FieldValue.increment(item.quantity),
          });
        }
      }

      // Notify user
      const userSnap = await db.collection("users").doc(orderData.userId).get();
      const fcmToken = userSnap.data()?.fcmToken;

      if (fcmToken) {
        await safeSendFCM({
          token: fcmToken,
          notification: {
            title: "Order Expired",
            body: `Order #${doc.id.substring(0, 8)} was cancelled — GCash payment not completed in time.`,
          },
          data: { type: "order", orderId: doc.id },
        }, orderData.userId);
      }
    }

    await batch.commit();
    logger.info(`Cleaned up ${count} abandoned GCash orders.`);
    return null;
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