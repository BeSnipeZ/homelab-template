'use strict'
const $ = (s) => document.querySelector(s)
const el = (tag, props = {}, ...kids) => {
  const n = Object.assign(document.createElement(tag), props)
  n.append(...kids)
  return n
}

async function api(path, opts = {}) {
  const r = await fetch(path, { ...opts, headers: { 'Content-Type': 'application/json' } })
  if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || r.statusText)
  return r.status === 204 ? null : r.json()
}

const ago = (iso) => {
  const m = Math.round((Date.now() - new Date(iso)) / 60000)
  return m < 1 ? 'just now' : m < 120 ? `${m} min ago` : `${Math.round(m / 60)} h ago`
}
const dur = (s) => (s > 86400 ? `${Math.floor(s / 86400)} d ` : '') + `${Math.floor((s % 86400) / 3600)} h`

async function loadStatus() {
  const s = await api('/api/status')
  const facts = [['Host', s.host], ['Uptime', dur(s.uptimeS)], ['Load', s.load[0].toFixed(2)],
    ['Memory', `${s.memTotalMB - s.memFreeMB} / ${s.memTotalMB} MB`]]
  if (s.tempC != null) facts.push(['CPU temp', `${s.tempC.toFixed(1)} °C`])
  $('#pi').replaceChildren(...facts.flatMap(([k, v]) => [el('dt', { textContent: k }), el('dd', { textContent: v })]))
  $('#services').replaceChildren(...s.services.map((x) =>
    el('li', { className: x.state === 'active' ? 'ok' : 'bad' }, el('span', { textContent: x.name }), el('span', { textContent: x.state }))))
  const stale = (iso) => Date.now() - new Date(iso) > 30 * 60000
  $('#pcs').replaceChildren(...(s.pcs.length ? s.pcs.map((p) =>
    el('li', { className: stale(p.seenAt) ? 'bad' : 'ok' }, el('span', { textContent: p.host }),
      el('span', { textContent: `${ago(p.seenAt)}${p.diskFreePct != null ? ` · ${p.diskFreePct}% free` : ''}` })))
    : [el('li', { className: 'muted', textContent: 'No heartbeat yet (run setup.ps1 on the PC).' })]))
}

async function loadTodos() {
  const todos = await api('/api/todos')
  const today = new Date().toISOString().slice(0, 10)
  $('#todos').replaceChildren(...todos.map((t) => {
    const box = el('input', { type: 'checkbox', checked: !!t.done, ariaLabel: `Done: ${t.text}` })
    box.onchange = () => api(`/api/todos/${t.id}`, { method: 'PATCH', body: JSON.stringify({ done: box.checked }) }).then(loadTodos, report)
    const del = el('button', { className: 'ghost', textContent: '×', ariaLabel: `Delete ${t.text}` })
    del.onclick = () => api(`/api/todos/${t.id}`, { method: 'DELETE' }).then(loadTodos, report)
    const due = t.due ? el('span', { className: 'due' + (!t.done && t.due < today ? ' late' : ''), textContent: t.due }) : ''
    return el('li', { className: t.done ? 'done' : '' }, box, el('span', { className: 'txt', textContent: t.text }), due, del)
  }))
}

function report(e) { $('#net').textContent = e.message; $('#net').className = 'pill bad' }

$('#add').onsubmit = async (ev) => {
  ev.preventDefault()
  const f = ev.target
  try {
    await api('/api/todos', { method: 'POST', body: JSON.stringify({ text: f.text.value, due: f.due.value || null }) })
    f.reset(); loadTodos()
  } catch (e) { report(e) }
}

function refresh() {
  Promise.all([loadStatus(), loadTodos()]).then(() => { $('#net').textContent = 'online'; $('#net').className = 'pill' },
    () => { $('#net').textContent = 'offline'; $('#net').className = 'pill bad' })
}
refresh()
setInterval(refresh, 60000)
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js')
