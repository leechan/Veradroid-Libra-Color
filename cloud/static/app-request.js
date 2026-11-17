// 申请适配: upload the APK in chunks (Cloudflare caps one request at 100 MB). Without JS the form posts normally.
(function () {
  var form = document.getElementById('appRequest');
  if (!form || !window.fetch || !window.FormData || !window.Blob) return;
  var msg = document.getElementById('reqMsg'), prog = document.getElementById('reqProgress'), btn = document.getElementById('reqBtn');
  function show(text, bad) { msg.textContent = text; msg.className = bad ? 'error' : 'ok'; }
  form.addEventListener('submit', async function (e) {
    var file = form.querySelector('input[type=file]').files[0];
    if (!file) return;
    e.preventDefault();
    var max = parseInt(form.dataset.max, 10), csrf = form.querySelector('input[name=_csrf]').value;
    if (!/\.apk$/i.test(file.name)) { show('只接受 .apk 文件。', true); return; }
    if (file.size > max) { show('文件超过 ' + Math.round(max / 1048576) + ' MB。', true); return; }
    btn.disabled = true; prog.textContent = '准备上传…';
    try {
      var init = new FormData();
      init.append('_csrf', csrf); init.append('filename', file.name); init.append('size', String(file.size));
      ['label', 'model', 'note'].forEach(function (n) { init.append(n, form.elements[n].value); });
      var r = await fetch('/apps/request/init', { method: 'POST', body: init, credentials: 'same-origin' });
      var j = await r.json().catch(function () { return {}; });
      if (!r.ok) throw new Error(j.error || ('初始化失败 ' + r.status));
      var size = j.chunk_size, total = Math.ceil(file.size / size);
      for (var i = 0; i < total; i++) {
        var c = await fetch('/apps/request/chunk?upload_id=' + j.upload_id + '&index=' + i, {
          method: 'POST', credentials: 'same-origin',
          headers: { 'Content-Type': 'application/octet-stream', 'X-CSRF-Token': csrf },
          body: file.slice(i * size, Math.min(file.size, (i + 1) * size))
        });
        if (!c.ok) { var cj = await c.json().catch(function () { return {}; }); throw new Error(cj.error || ('上传失败 ' + c.status)); }
        prog.textContent = '上传中 ' + Math.round((i + 1) * 100 / total) + '%（' + (file.size / 1048576).toFixed(1) + ' MB）';
      }
      prog.textContent = '校验中…';
      var fin = new FormData(); fin.append('_csrf', csrf); fin.append('upload_id', j.upload_id);
      var f = await fetch('/apps/request/finish', { method: 'POST', body: fin, credentials: 'same-origin' });
      var fj = await f.json().catch(function () { return {}; });
      if (!f.ok) throw new Error(fj.error || ('提交失败 ' + f.status));
      show(fj.message || '已提交。', false); prog.textContent = '';
      setTimeout(function () { location.href = fj.redirect || '/apps/requests/mine'; }, 1500);
    } catch (err) {
      show(err.message, true); prog.textContent = ''; btn.disabled = false;
    }
  });
})();
