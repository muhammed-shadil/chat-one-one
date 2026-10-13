// Shows push notifications for new messages while the website is closed or in
// a background tab. Firebase Messaging loads this file from the site root.
// The version matches the Firebase JS SDK used by firebase_core_web.
importScripts('https://www.gstatic.com/firebasejs/12.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.13.0/firebase-messaging-compat.js');

// Same values as `web` in lib/firebase_options.dart.
firebase.initializeApp({
  apiKey: 'AIzaSyAh3oxnGhBUScI3i3_kg-xhaOL9bGria4c',
  appId: '1:413042106712:web:3e02d0dc90fb12f4ec052d',
  messagingSenderId: '413042106712',
  projectId: 'chat-one-one-66cbf',
  authDomain: 'chat-one-one-66cbf.firebaseapp.com',
  storageBucket: 'chat-one-one-66cbf.firebasestorage.app',
});

// Notifications from the notifyNewMessage Cloud Function carry their own
// title, text and link, so Firebase displays them without extra code here.
firebase.messaging();
