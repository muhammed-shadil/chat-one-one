// What a push notification says about a new message.

// Title and text for [message] from [senderName]. View-once photos never show
// anything of the photo.
function notificationFor(message, senderName) {
  const body = (() => {
    switch (message.type) {
      case 'text':
        return message.text || '';
      case 'image':
        if (message.viewOnce) return '📷 View once photo';
        return `📷 ${message.text || 'Photo'}`;
      case 'audio':
        return `🎤 Voice message (${formatDuration(message.durationMs || 0)})`;
      case 'file':
        return `📄 ${message.fileName || 'File'}`;
      default:
        return 'New message';
    }
  })();
  return { title: senderName || 'New message', body: clip(body, 200) };
}

// "0:07", "12:45", matching formatDuration in lib/utils/format.dart.
function formatDuration(ms) {
  const s = Math.floor(ms / 1000);
  const mmss = `${Math.floor(s / 60) % 60}:${String(s % 60).padStart(2, '0')}`;
  return s < 3600 ? mmss : `${Math.floor(s / 3600)}:${mmss.padStart(5, '0')}`;
}

function clip(text, max) {
  return text.length <= max ? text : `${text.slice(0, max)}…`;
}

module.exports = { notificationFor, formatDuration };
