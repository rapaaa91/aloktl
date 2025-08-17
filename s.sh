#!/usr/bin/env bash
set -euo pipefail

APP_NAME="xentra-panel"

# --- Cek dependensi ---
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Harus ada $1"; exit 1; }; }
need_cmd node
need_cmd npm
need_cmd npx

# --- Buat folder proyek ---
mkdir -p "$APP_NAME"
cd "$APP_NAME"

echo "🔧 Inisialisasi $APP_NAME ..."
npm init -y >/dev/null

# --- Install dependencies ---
echo "📦 Installing dependencies..."
npm install express ejs cookie-parser jsonwebtoken bcryptjs zod helmet morgan csurf dotenv
npm install -D nodemon prisma @prisma/client

# --- Ubah package.json ---
node - <<'NODE'
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync("package.json","utf8"));
pkg.type = "module";
pkg.scripts = {
  dev:"nodemon --watch src --ext js,ejs --exec node src/server.js",
  start:"node src/server.js",
  "prisma:studio":"npx prisma studio"
};
fs.writeFileSync("package.json", JSON.stringify(pkg,null,2));
NODE

# --- Buat file ENV ---
cat > .env <<'ENV'
PORT=3000
NODE_ENV=development
JWT_SECRET=
CSRF_SECRET=
SESSION_COOKIE_NAME=xentra.sid
DATABASE_URL="file:./dev.db"
ENV

# --- Generate secrets pakai Node.js ---
JWT_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
CSRF_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" .env
sed -i "s|^CSRF_SECRET=.*|CSRF_SECRET=${CSRF_SECRET}|" .env

# --- Prisma init ---
npx prisma init --datasource-provider sqlite >/dev/null

cat > prisma/schema.prisma <<'PRISMA'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "sqlite"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String
  password  String
  role      Role     @default(USER)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
}

enum Role {
  ADMIN
  USER
}
PRISMA

# --- Buat struktur src dasar ---
mkdir -p src/{routes,controllers,middleware,utils,views/{layouts,partials,admin}}

# server.js
cat > src/server.js <<'JS'
import express from "express";
import morgan from "morgan";
import helmet from "helmet";
import cookieParser from "cookie-parser";
import csrf from "csurf";
import dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

app.use(helmet());
app.use(morgan("dev"));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(cookieParser());
app.use(csrf({ cookie: true }));

app.set("view engine", "ejs");
app.set("views", path.join(__dirname, "views"));

import indexRoutes from "./routes/index.js";
import authRoutes from "./routes/auth.js";
import adminRoutes from "./routes/admin.js";

app.use("/", indexRoutes);
app.use("/auth", authRoutes);
app.use("/admin", adminRoutes);

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).send("Something broke!");
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Xentra running at http://127.0.0.1:${PORT}`);
});
JS

# routes/index.js
cat > src/routes/index.js <<'JS'
import { Router } from "express";

const router = Router();

router.get("/", (req, res) => {
  res.render("index", { title: "Xentra Dashboard" });
});

export default router;
JS

# routes/auth.js
cat > src/routes/auth.js <<'JS'
import { Router } from "express";

const router = Router();

router.get("/login", (req, res) => {
  res.render("login", { title: "Login" });
});

router.get("/register", (req, res) => {
  res.render("register", { title: "Register" });
});

export default router;
JS

# routes/admin.js
cat > src/routes/admin.js <<'JS'
import { Router } from "express";

const router = Router();

router.get("/users", (req, res) => {
  res.render("admin/users", { title: "Manage Users" });
});

export default router;
JS

# --- Views ---
cat > src/views/layouts/base.ejs <<'EJS'
<!DOCTYPE html>
<html>
<head>
  <title><%= title %> | Xentra</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
</head>
<body>
  <header>
    <h1>Xentra Panel</h1>
    <nav>
      <ul>
        <li><a href="/">Dashboard</a></li>
        <li><a href="/auth/login">Login</a></li>
        <li><a href="/auth/register">Register</a></li>
        <li><a href="/admin/users">Admin</a></li>
      </ul>
    </nav>
  </header>
  <main class="container">
    <%- body %>
  </main>
  <footer>
    <small>Powered by Xentra</small>
  </footer>
</body>
</html>
EJS

cat > src/views/index.ejs <<'EJS'
<% layout('layouts/base') %>
<h2>Welcome to Xentra Dashboard</h2>
<p>This is the main panel page.</p>
EJS

cat > src/views/login.ejs <<'EJS'
<% layout('layouts/base') %>
<h2>Login</h2>
<form method="post" action="/auth/login">
  <label>Email: <input type="email" name="email" required></label>
  <label>Password: <input type="password" name="password" required></label>
  <button type="submit">Login</button>
</form>
EJS

cat > src/views/register.ejs <<'EJS'
<% layout('layouts/base') %>
<h2>Register</h2>
<form method="post" action="/auth/register">
  <label>Name: <input type="text" name="name" required></label>
  <label>Email: <input type="email" name="email" required></label>
  <label>Password: <input type="password" name="password" required></label>
  <button type="submit">Register</button>
</form>
EJS

mkdir -p src/views/admin
cat > src/views/admin/users.ejs <<'EJS'
<% layout('../layouts/base') %>
<h2>User Management</h2>
<p>List of users will appear here.</p>
EJS

echo "✅ Struktur Xentra (Termux edition) selesai dibuat."
echo
echo "Langkah selanjutnya:"
echo "1) cd $APP_NAME"
echo "2) npx prisma migrate dev --name init"
echo "3) npm run dev"
echo
echo "Login admin default: belum ada (buat user manual lewat Prisma Studio)."
