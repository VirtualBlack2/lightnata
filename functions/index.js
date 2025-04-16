const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.sendPushNotification = onDocumentWritten("announcements/latest", (event) => {
  const after = event.data.after?.data();

  if (!after || !after.text) return;

  const payload = {
    notification: {
      title: "📢 NAWEC ANNOUNCEMENT",
      body: after.text,
    },
    topic: "announcements",
  };

  return getMessaging().send(payload)
    .then(res => console.log("✅ Push sent:", res))
    .catch(err => console.error("❌ Push error:", err));
});
