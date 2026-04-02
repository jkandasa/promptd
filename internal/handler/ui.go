package handler

const htmlUI = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Chatbot</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: system-ui, sans-serif; background: #f0f2f5; height: 100vh; display: flex; align-items: center; justify-content: center; }
    #app { width: 100%; max-width: 720px; height: 90vh; display: flex; flex-direction: column; background: #fff; border-radius: 12px; box-shadow: 0 4px 24px rgba(0,0,0,.1); overflow: hidden; }
    #header { padding: 16px 20px; background: #1a1a2e; color: #fff; display: flex; justify-content: space-between; align-items: center; }
    #header h1 { font-size: 1.1rem; font-weight: 600; }
    #reset-btn { background: transparent; border: 1px solid rgba(255,255,255,.4); color: #fff; padding: 4px 12px; border-radius: 6px; cursor: pointer; font-size: .85rem; }
    #reset-btn:hover { background: rgba(255,255,255,.1); }
    #messages { flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 12px; }
    .msg { max-width: 80%; padding: 10px 14px; border-radius: 12px; line-height: 1.5; font-size: .95rem; white-space: pre-wrap; word-break: break-word; }
    .msg.user { align-self: flex-end; background: #1a1a2e; color: #fff; border-bottom-right-radius: 4px; }
    .msg.assistant { align-self: flex-start; background: #f0f2f5; color: #1a1a2e; border-bottom-left-radius: 4px; }
    .msg.error { align-self: center; background: #ffe0e0; color: #c00; font-size: .85rem; }
    #form { padding: 16px; border-top: 1px solid #e5e7eb; display: flex; gap: 10px; }
    #input { flex: 1; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: .95rem; outline: none; resize: none; height: 44px; line-height: 1.4; }
    #input:focus { border-color: #1a1a2e; }
    #send-btn { padding: 10px 20px; background: #1a1a2e; color: #fff; border: none; border-radius: 8px; cursor: pointer; font-size: .95rem; font-weight: 500; }
    #send-btn:disabled { opacity: .5; cursor: not-allowed; }
    #send-btn:hover:not(:disabled) { background: #16213e; }
    .typing { align-self: flex-start; color: #9ca3af; font-size: .85rem; padding: 6px 0; }
  </style>
</head>
<body>
<div id="app">
  <div id="header">
    <h1>Chatbot</h1>
    <button id="reset-btn">New Chat</button>
  </div>
  <div id="messages"></div>
  <form id="form">
    <textarea id="input" placeholder="Type a message..." rows="1"></textarea>
    <button id="send-btn" type="submit">Send</button>
  </form>
</div>

<script>
  const sessionId = crypto.randomUUID();
  const messages = document.getElementById('messages');
  const input = document.getElementById('input');
  const sendBtn = document.getElementById('send-btn');

  function addMessage(role, text) {
    const el = document.createElement('div');
    el.className = 'msg ' + role;
    el.textContent = text;
    messages.appendChild(el);
    messages.scrollTop = messages.scrollHeight;
    return el;
  }

  async function send() {
    const text = input.value.trim();
    if (!text) return;

    input.value = '';
    sendBtn.disabled = true;
    addMessage('user', text);

    const typing = document.createElement('div');
    typing.className = 'typing';
    typing.textContent = 'Thinking...';
    messages.appendChild(typing);
    messages.scrollTop = messages.scrollHeight;

    try {
      const res = await fetch('/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: sessionId, message: text }),
      });
      const data = await res.json();
      typing.remove();
      if (!res.ok) {
        addMessage('error', data.error || 'Something went wrong');
      } else {
        addMessage('assistant', data.reply);
      }
    } catch (e) {
      typing.remove();
      addMessage('error', 'Network error: ' + e.message);
    } finally {
      sendBtn.disabled = false;
      input.focus();
    }
  }

  document.getElementById('form').addEventListener('submit', e => { e.preventDefault(); send(); });

  input.addEventListener('keydown', e => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
  });

  document.getElementById('reset-btn').addEventListener('click', async () => {
    await fetch('/reset', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: sessionId }),
    });
    messages.innerHTML = '';
    input.focus();
  });
</script>
</body>
</html>`
