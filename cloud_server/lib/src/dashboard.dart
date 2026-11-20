/// Consola web del backend ("consola nube") para validar la subida
/// automática de registros y provocar colisiones desde "otro dispositivo".
const dashboardHtml = r'''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Consola Nube · Offline-First</title>
<style>
  :root{--bg:#0f172a;--panel:#111c33;--line:#1e2a44;--text:#e2e8f0;--muted:#94a3b8;
        --blue:#0284c7;--teal:#14b8a6;--amber:#f59e0b;--red:#ef4444;--green:#22c55e}
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--text);
  font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
  header{padding:24px 32px;border-bottom:1px solid var(--line);display:flex;gap:16px;
         align-items:center;justify-content:space-between;flex-wrap:wrap}
  .eyebrow{color:var(--teal);font-size:12px;letter-spacing:.12em;font-weight:700;text-transform:uppercase}
  h1{margin:4px 0 0;font-size:24px} main{padding:24px 32px;display:grid;gap:24px}
  .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:16px}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:18px}
  .num{font-size:30px;font-weight:800} .lbl{color:var(--muted);font-size:12px}
  table{width:100%;border-collapse:collapse} th,td{text-align:left;padding:10px 12px;border-bottom:1px solid var(--line)}
  th{color:var(--muted);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.06em}
  tr.flash{animation:flash 2.2s ease-out} @keyframes flash{from{background:#14b8a633}to{background:transparent}}
  .pill{display:inline-block;padding:2px 9px;border-radius:999px;font-size:12px;font-weight:600}
  .ok{background:#22c55e22;color:var(--green)} .del{background:#ef444422;color:var(--red)}
  .src-device{background:#0284c722;color:#38bdf8} .src-console{background:#f59e0b22;color:var(--amber)}
  button{background:var(--blue);color:#fff;border:0;border-radius:8px;padding:7px 12px;font-weight:600;cursor:pointer}
  button.ghost{background:transparent;border:1px solid var(--line);color:var(--text)}
  button.warn{background:var(--amber);color:#111}
  .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap} .muted{color:var(--muted)}
  code{color:#7dd3fc} .dot{width:10px;height:10px;border-radius:50%;display:inline-block;background:var(--green)}
  .dot.off{background:var(--red)} .wrap{overflow-x:auto}
  .done{text-decoration:line-through;color:var(--muted)}
</style>
</head>
<body>
<header>
  <div>
    <div class="eyebrow">Desarrollo Móvil Integral · Semana 11</div>
    <h1>Consola Nube — Sincronización Offline-First</h1>
  </div>
  <div class="row">
    <span class="dot" id="dot"></span><span id="status" class="muted">Conectando…</span>
    <button class="warn" id="maint">Simular caída del servidor</button>
  </div>
</header>
<main>
  <section class="stats">
    <div class="card"><div class="num" id="sUsers">0</div><div class="lbl">Usuarios registrados</div></div>
    <div class="card"><div class="num" id="sTasks">0</div><div class="lbl">Registros activos en la nube</div></div>
    <div class="card"><div class="num" id="sDeleted">0</div><div class="lbl">Borrados lógicos (tombstones)</div></div>
    <div class="card"><div class="num" id="sSeq">0</div><div class="lbl">Cursor del servidor (server_seq)</div></div>
  </section>

  <section class="card">
    <div class="row" style="justify-content:space-between">
      <h3 style="margin:0">Usuarios</h3>
      <span class="muted">Crea una tarea “desde la nube” para validar el PULL en el dispositivo.</span>
    </div>
    <div class="wrap"><table><thead><tr><th>UID</th><th>Correo</th><th>Tareas</th><th></th></tr></thead>
    <tbody id="users"></tbody></table></div>
  </section>

  <section class="card">
    <div class="row" style="justify-content:space-between">
      <h3 style="margin:0">Registros sincronizados</h3>
      <span class="muted">“Editar en la nube” simula otro dispositivo para provocar una colisión (LWW).</span>
    </div>
    <div class="wrap"><table>
      <thead><tr><th>Título</th><th>Usuario</th><th>Estado</th><th>Versión</th><th>updated_at (UTC)</th><th>Origen</th><th>seq</th><th></th></tr></thead>
      <tbody id="tasks"></tbody>
    </table></div>
  </section>
</main>
<script>
const key = new URLSearchParams(location.search).get('key') || '';
const H = {'x-admin-key': key, 'content-type': 'application/json'};
let seen = new Set(), firstLoad = true, state = null;
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

async function refresh(){
  try{
    const r = await fetch('/admin/state', {headers:H});
    if(r.status===403){ setStatus(false,'Abre la URL con ?key= que imprimió el servidor'); return; }
    state = await r.json(); render(); setStatus(!state.maintenance, state.maintenance ? 'En mantenimiento (503)' : 'Servidor en línea');
  }catch(e){ setStatus(false,'Servidor no disponible'); }
}
function setStatus(ok,msg){ document.getElementById('dot').className='dot'+(ok?'':' off'); document.getElementById('status').textContent=msg;
  if(state) document.getElementById('maint').textContent = state.maintenance ? 'Restablecer servidor' : 'Simular caída del servidor'; }
function render(){
  const emails = Object.fromEntries(state.users.map(u=>[u.uid,u.email]));
  const active = state.tasks.filter(t=>!t.is_deleted);
  sUsers.textContent = state.users.length; sTasks.textContent = active.length;
  sDeleted.textContent = state.tasks.length - active.length; sSeq.textContent = state.serverSeq;
  users.innerHTML = state.users.map(u=>`<tr><td><code>${esc(u.uid)}</code></td><td>${esc(u.email)}</td>
    <td>${active.filter(t=>t.owner_uid===u.uid).length}</td>
    <td><button class="ghost" onclick="createFor('${u.uid}')">+ Crear tarea en la nube</button></td></tr>`).join('')
    || '<tr><td colspan="4" class="muted">Aún no hay usuarios. Regístrate desde la app.</td></tr>';
  tasks.innerHTML = state.tasks.map(t=>{
    const key = t.id+'@'+t.server_seq; const isNew = !firstLoad && !seen.has(key); seen.add(key);
    return `<tr class="${isNew?'flash':''}">
      <td class="${t.is_completed?'done':''}"><b>${esc(t.title)}</b><div class="muted">${esc(t.description)}</div></td>
      <td>${esc(emails[t.owner_uid]||t.owner_uid)}</td>
      <td>${t.is_deleted?'<span class="pill del">Eliminada</span>':t.is_completed?'<span class="pill ok">Completada</span>':'<span class="pill">Abierta</span>'}</td>
      <td>v${t.version}</td><td><code>${esc(t.updated_at)}</code></td>
      <td><span class="pill src-${t.last_source}">${t.last_source==='console'?'Consola':'Dispositivo'}</span></td>
      <td>${t.server_seq}</td>
      <td class="row">${t.is_deleted?'':`<button class="ghost" onclick="editTask('${t.id}')">Editar en la nube</button>
        <button class="ghost" onclick="toggle('${t.id}',${t.is_completed?0:1})">${t.is_completed?'Reabrir':'Completar'}</button>`}</td></tr>`;}).join('')
    || '<tr><td colspan="8" class="muted">Sin registros todavía. Crea tareas en la app (aunque estés offline) y observa cómo llegan aquí.</td></tr>';
  firstLoad = false;
}
async function editTask(id){
  const t = state.tasks.find(x=>x.id===id); const title = prompt('Nuevo título (simula edición desde otro dispositivo):', t.title);
  if(title===null||!title.trim()) return;
  await fetch('/admin/tasks/'+id,{method:'POST',headers:H,body:JSON.stringify({title})}); refresh();
}
async function toggle(id,v){ await fetch('/admin/tasks/'+id,{method:'POST',headers:H,body:JSON.stringify({is_completed:v})}); refresh(); }
async function createFor(uid){
  const title = prompt('Título de la tarea creada en la nube:','Revisar evidencias de la Unidad II'); if(!title) return;
  await fetch('/admin/users/'+uid+'/tasks',{method:'POST',headers:H,body:JSON.stringify({title})}); refresh();
}
maint.onclick = async ()=>{ await fetch('/admin/maintenance',{method:'POST',headers:H,body:JSON.stringify({enabled:!state?.maintenance})}); refresh(); };
refresh(); setInterval(refresh, 1500);
</script>
</body>
</html>
''';
