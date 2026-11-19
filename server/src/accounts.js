'use strict';

const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { promisify } = require('node:util');
const { DatabaseSync } = require('node:sqlite');

const scrypt = promisify(crypto.scrypt);

class Accounts {
  constructor(filename, tokenTtlMs, scryptCost) {
    if (filename !== ':memory:') fs.mkdirSync(path.dirname(path.resolve(filename)), { recursive: true });
    this.db = new DatabaseSync(filename);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA foreign_keys = ON;
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS sessions (
        token_hash TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        expires_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS sessions_expiry ON sessions(expires_at);
    `);
    this.tokenTtlMs = tokenTtlMs;
    this.scryptCost = scryptCost;
    this.insertUser = this.db.prepare('INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)');
    this.findUser = this.db.prepare('SELECT * FROM users WHERE username = ?');
    this.insertSession = this.db.prepare('INSERT INTO sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)');
    this.findSession = this.db.prepare(`SELECT users.username, sessions.token_hash FROM sessions
      JOIN users ON users.id = sessions.user_id
      WHERE sessions.token_hash = ? AND sessions.expires_at > ?`);
    this.deleteSession = this.db.prepare('DELETE FROM sessions WHERE token_hash = ?');
    this.deleteExpiredSessions = this.db.prepare('DELETE FROM sessions WHERE expires_at <= ?');
  }

  async hashPassword(password) {
    const salt = crypto.randomBytes(16);
    const derived = await scrypt(password, salt, 64, { N: this.scryptCost, r: 8, p: 1 });
    return `scrypt$${this.scryptCost}$${salt.toString('base64')}$${derived.toString('base64')}`;
  }

  async verifyPassword(password, encoded) {
    const [algorithm, cost, salt, expected] = encoded.split('$');
    if (algorithm !== 'scrypt' || !/^[0-9]+$/.test(cost)) return false;
    const actual = await scrypt(password, Buffer.from(salt, 'base64'), 64, { N: Number(cost), r: 8, p: 1 });
    return crypto.timingSafeEqual(actual, Buffer.from(expected, 'base64'));
  }

  async register(username, password) {
    const hash = await this.hashPassword(password);
    this.db.exec('BEGIN');
    try {
      const { lastInsertRowid } = this.insertUser.run(username, hash, Date.now());
      const session = this.#issueSession(lastInsertRowid, username);
      this.db.exec('COMMIT');
      return session;
    } catch (error) {
      try {
        this.db.exec('ROLLBACK');
      } catch {
        // SQLite may have already rolled back after a write failure.
      }
      throw error;
    }
  }

  async login(username, password) {
    const user = this.findUser.get(username);
    if (!user) {
      // Unknown users still perform one password derivation.
      await this.hashPassword(password);
      return null;
    }
    if (!await this.verifyPassword(password, user.password_hash)) return null;
    return this.#issueSession(user.id, user.username);
  }

  #issueSession(userId, username) {
    const token = crypto.randomBytes(32).toString('base64url');
    const now = Date.now();
    this.deleteExpiredSessions.run(now);
    this.insertSession.run(tokenHash(token), userId, now + this.tokenTtlMs, now);
    return { username, token };
  }

  authenticate(token) {
    return this.findSession.get(tokenHash(token), Date.now());
  }

  revoke(token) {
    this.deleteSession.run(tokenHash(token));
  }

  close() {
    this.db.close();
  }
}

function tokenHash(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

// node:sqlite reports every SQL failure as ERR_SQLITE_ERROR and carries the
// extended result code separately; SQLITE_CONSTRAINT_UNIQUE is 2067.
const SQLITE_CONSTRAINT_UNIQUE = 2067;

function isUniqueViolation(error) {
  return error?.code === 'ERR_SQLITE_ERROR' &&
    (error.errcode === SQLITE_CONSTRAINT_UNIQUE || /UNIQUE constraint failed/.test(error.message || ''));
}

module.exports = { Accounts, isUniqueViolation };
