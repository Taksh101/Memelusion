const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.deleteExpiredMessages = functions.pubsub
  .schedule('every 1 minutes') // runs every minute
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    const chatsSnapshot = await admin.firestore().collection('chats').get();

    for (const chatDoc of chatsSnapshot.docs) {
      const messagesRef = chatDoc.ref.collection('messages');
      const expiredMessages = await messagesRef.where('expiresAt', '<=', now).get();

      if (!expiredMessages.empty) {
        const batch = admin.firestore().batch();
        expiredMessages.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
      }
    }
    return null;
  });