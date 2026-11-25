// Homelab dashboard: to-dos, Pi status, PC heartbeat. No dependencies (Node >= 22.13).
// Security model: binds to 127.0.0.1 and is published to your tailnet with
// `tailscale serve`, so the tailnet is the login. Browser writes must be
// same-origin (CSRF guard); machine writes (/api/pc) need DASHBOARD_TOKEN.
'use strict'
const { createServer } = require('node:http')
const { DatabaseSync } = require('node:sqlite')
const { execFile } = require('node:child_process')
const { readFile } = require('node:fs/promises')
const { timingSafeEqual, createHash } = require('node:crypto')
const os = require('node:os')
const path = require('node:path')

const PORT = Number(process.env.DASHBOARD_PORT || 3000)
const HOST = process.env.DASHBOARD_HOST || '127.0.0.1'
const TOKEN = process.env.DASHBOARD_TOKEN || ''
const SERVICES = (process.env.WATCH_SERVICES || '').split(/\s+/).filter((s) => /^[\w@][\w@.-]*$/.test(s)) // no leading '-' (would be a systemctl option)
const PUBLIC = path.join(__dirname, 'public')
const MAX_BODY = 64 * 1024

const db = new DatabaseSync(process.env.DB_PATH || path.join(__dirname, 'data.db'))
db.exec(`
  CREATE TABLE IF NOT EXISTS todos (
    id INTEGER PRIMARY KEY, text TEXT NOT NULL, due TEXT, done INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')));
  CREATE TABLE IF NOT EXISTS heartbeats (
    host TEXT PRIMARY KEY, seen_at TEXT NOT NULL, data TEXT NOT NULL);
`)

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.svg': 'image/svg+xml', '.png': 'image/png' }
const HEADERS = {
  'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
}

class HttpError extends Error { constructor(code, msg) { super(msg); this.code = code } }

function send(res, code, body, type = 'application/json') {
  res.writeHead(code, { ...HEADERS, 'Content-Type': type, 'Cache-Control': 'no-store' })
  res.end(type === 'application/json' ? JSON.stringify(body) : body)
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0
    const parts = []
    req.on('data', (c) => {
      size += c.length
      if (size > MAX_BODY) { reject(new HttpError(413, 'body too large')); req.destroy() } else parts.push(c)
    })
    req.on('end', () => {
      try { resolve(parts.length ? JSON.parse(Buffer.concat(parts).toString('utf8')) : {}) } catch { reject(new HttpError(400, 'invalid JSON')) }
    })
    req.on('error', reject)
  })
}

// DNS rebinding guard: a hostile site can point its own name at this server, then Origin and
// Host match. Real visitors arrive as an IP literal, localhost, *.ts.net or TS_HOST.
const TS_HOST = (process.env.TS_HOST || '').toLowerCase()
function hostOk(req) {
  let name
  try { name = new URL(`http://${req.headers.host}`).hostname.toLowerCase() } catch { return false }
  return name === 'localhost' || name === TS_HOST || name.endsWith('.ts.net') ||
    /^\d{1,3}(\.\d{1,3}){3}$/.test(name) || name.startsWith('[') // IPv4 / IPv6 literal
}

// Browser writes: the Origin header must match the Host (blocks cross-site form posts).
function sameOrigin(req) {
  const origin = req.headers.origin
  if (!origin) {
    const site = req.headers['sec-fetch-site']
    return !site || site === 'same-origin' || site === 'none' // curl & co. send neither header
  }
  try { return new URL(origin).host === req.headers.host } catch { return false }
}

function tokenOk(req) {
  if (!TOKEN) return false
  const given = (req.headers.authorization || '').replace(/^Bearer\s+/i, '')
  const a = createHash('sha256').update(given).digest()
  const b = createHash('sha256').update(TOKEN).digest()
  return timingSafeEqual(a, b)
}

function todoInput(body) {
  const text = typeof body.text === 'string' ? body.text.trim() : ''
  if (!text || text.length > 500) throw new HttpError(400, 'text: 1-500 characters')
  const due = body.due == null || body.due === '' ? null : String(body.due)
  if (due && !/^\d{4}-\d{2}-\d{2}$/.test(due)) throw new HttpError(400, 'due: YYYY-MM-DD')
  return { text, due }
}

function systemctlState(unit) {
  return new Promise((resolve) => {
    execFile('systemctl', ['is-active', unit], { timeout: 3000 }, (err, out) => resolve((out || '').trim() || (err ? 'unknown' : 'active')))
  })
}

async function status() {
  const services = await Promise.all(SERVICES.map(async (name) => ({ name, state: await systemctlState(name) })))
  let tempC = null
  try { tempC = Number(await readFile('/sys/class/thermal/thermal_zone0/temp', 'utf8')) / 1000 } catch { /* not a Pi */ }
  const pcs = db.prepare('SELECT host, seen_at, data FROM heartbeats ORDER BY host').all()
    .map((r) => ({ host: r.host, seenAt: r.seen_at, ...JSON.parse(r.data) }))
  return { host: os.hostname(), uptimeS: Math.round(os.uptime()), load: os.loadavg(), memFreeMB: Math.round(os.freemem() / 2 ** 20),
    memTotalMB: Math.round(os.totalmem() / 2 ** 20), tempC, services, pcs }
}

async function api(req, res, url) {
  const m = req.method
  const p = url.pathname
  if (m !== 'GET' && p !== '/api/pc' && !sameOrigin(req)) throw new HttpError(403, 'cross-origin write blocked')

  if (p === '/api/health' && m === 'GET') return send(res, 200, { ok: true })
  if (p === '/api/status' && m === 'GET') return send(res, 200, await status())

  if (p === '/api/todos' && m === 'GET') return send(res, 200, db.prepare('SELECT * FROM todos ORDER BY done, due IS NULL, due, id').all())
  if (p === '/api/todos' && m === 'POST') {
    const { text, due } = todoInput(await readJson(req))
    const r = db.prepare('INSERT INTO todos (text, due) VALUES (?, ?)').run(text, due)
    return send(res, 201, db.prepare('SELECT * FROM todos WHERE id = ?').get(r.lastInsertRowid))
  }
  const t = p.match(/^\/api\/todos\/(\d+)$/)
  if (t && m === 'PATCH') {
    const body = await readJson(req)
    const row = db.prepare('SELECT * FROM todos WHERE id = ?').get(Number(t[1]))
    if (!row) throw new HttpError(404, 'not found')
    const next = 'text' in body || 'due' in body ? todoInput({ text: body.text ?? row.text, due: 'due' in body ? body.due : row.due }) : row
    const done = 'done' in body ? (body.done ? 1 : 0) : row.done
    db.prepare('UPDATE todos SET text = ?, due = ?, done = ? WHERE id = ?').run(next.text, next.due, done, row.id)
    return send(res, 200, db.prepare('SELECT * FROM todos WHERE id = ?').get(row.id))
  }
  if (t && m === 'DELETE') {
    db.prepare('DELETE FROM todos WHERE id = ?').run(Number(t[1]))
    return send(res, 204, '', 'text/plain')
  }

  if (p === '/api/pc' && m === 'POST') {
    if (!tokenOk(req)) throw new HttpError(401, 'bad token')
    const body = await readJson(req)
    const host = typeof body.host === 'string' ? body.host.slice(0, 64) : ''
    if (!/^[\w.-]+$/.test(host)) throw new HttpError(400, 'host: letters, digits, . _ -')
    const data = { diskFreePct: Number(body.diskFreePct) || null, uptimeH: Number(body.uptimeH) || null, note: String(body.note || '').slice(0, 200) }
    db.prepare('INSERT INTO heartbeats (host, seen_at, data) VALUES (?, ?, ?) ON CONFLICT(host) DO UPDATE SET seen_at = excluded.seen_at, data = excluded.data')
      .run(host, new Date().toISOString(), JSON.stringify(data))
    return send(res, 204, '', 'text/plain')
  }
  throw new HttpError(404, 'not found')
}

async function staticFile(res, pathname) {
  let rel
  try { rel = pathname === '/' ? 'index.html' : decodeURIComponent(pathname).replace(/^\/+/, '') } catch { return send(res, 404, { error: 'not found' }) }
  const file = path.resolve(PUBLIC, rel)
  if (!file.startsWith(PUBLIC + path.sep)) return send(res, 404, { error: 'not found' })
  try {
    const body = await readFile(file)
    res.writeHead(200, { ...HEADERS, 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' })
    res.end(body)
  } catch { send(res, 404, { error: 'not found' }) }
}

const server = createServer(async (req, res) => {
  try {
    if (!hostOk(req)) throw new HttpError(421, 'unknown host')
    const url = new URL(req.url, 'http://x')
    if (url.pathname.startsWith('/api/')) await api(req, res, url)
    else if (req.method === 'GET' || req.method === 'HEAD') await staticFile(res, url.pathname)
    else send(res, 405, { error: 'method not allowed' })
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    if (!res.headersSent) send(res, e.code || 500, { error: e instanceof HttpError ? e.message : 'internal error' })
  }
})

if (require.main === module) server.listen(PORT, HOST, () => console.log(`dashboard on http://${HOST}:${PORT}`))
module.exports = { server, db }
