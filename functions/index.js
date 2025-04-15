const functions = require("firebase-functions");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

admin.initializeApp();

exports.sendAnnouncementNotification = functions.firestore
  .document("announcements/{announcementId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const messageText = data.text;

    const payload = {
      notification: {
        title: "📢 New Announcement",
        body: messageText,
      },
      topic: "announcements", // All devices subscribed to 'announcements' will get this
    };

    try {
      await admin.messaging().send(payload);
      console.log("✅ Notification sent successfully");
    } catch (error) {
      console.error("❌ Error sending notification:", error);
    }
  });
