# คู่มือระบบ Multiplayer WebRTC & Room Code (ใครก็สร้างห้องได้)

ระบบนี้ใช้ **WebRTC + Signaling Relay** ทำให้ **ผู้เล่นทุกคนสามารถกด "สร้างห้อง" ได้ทันที ไม่ว่าจะเล่นผ่านเว็บ (HTML5), มือถือ หรือคอมพิวเตอร์** โดยไม่มีปัญหา `Error code: 20` และไม่ต้องตั้งค่า Forward Port ในเร้าเตอร์

---

## 1. วิธีเปิดทดสอบบนเครื่องตนเอง (Local Test)

เครื่องคอมพิวเตอร์ของคุณมี Node.js ติดตั้งอยู่แล้ว สามารถเปิดเซิร์ฟเวอร์จับคู่ได้ทันที:

1. เปิด Terminal หรือ PowerShell ในโฟลเดอร์เกม
2. รันคำสั่ง:
   ```bash
   node server/signaling_server.js
   ```
3. จะขึ้นข้อความ:
   ```
   ===============================================
	WebRTC Signaling Server listening on port 9080
	Ready for Room Codes & P2P Matchmaking!
   ===============================================
   ```
4. ในหน้าเมนูเกม:
   - ผู้เล่นคนที่ 1 กด **"สร้างห้อง"** -> จะได้รับรหัสห้อง 4 หลัก (เช่น `K8M2`)
   - ผู้เล่นคนที่ 2 กด **"เข้าร่วมห้อง"** -> กรอกรหัส `K8M2` -> กดเชื่อมต่อเข้าห้องได้ทันที!
   - เมื่อพร้อมแล้ว Host กด **"เริ่มเกมเลย"**

---

## 2. วิธีเอาขึ้น Cloud ฟรี 24/7 (เล่นออนไลน์ได้ทั่วโลกผ่านเว็บ GitHub Pages)

เมื่อต้องการให้คนเล่นผ่าน `https://fimlnwza007.github.io/In-the-dark/` เล่นออนไลน์กับเพื่อนได้ทั่วโลก โดยไม่ต้องเปิดคอมทิ้งไว้ ให้เอาโฟลเดอร์ `server/` ขึ้นบริการฟรีดังนี้:

### ตัวเลือก A: Glitch.com (ง่ายและเร็วที่สุด - 1 นาทีเสร็จ)
1. ไปที่ [Glitch.com](https://glitch.com) (สมัครสมาชิกฟรี)
2. กดปุ่ม **New Project** -> เลือก **Import from GitHub**
3. หรือสร้างโปรเจกต์เปล่าแบบ **hello-node** แล้วคัดลอกโค้ดจาก `server/signaling_server.js` และ `server/package.json` ไปวาง
4. Glitch จะให้ URL ของคุณ เช่น `https://alone-in-the-dusk.glitch.me`
5. เปลี่ยนเป็นโปรโตคอล WebSocket:
   `wss://alone-in-the-dusk.glitch.me`
6. นำ URL นี้ไปใส่ในตัวแปร `signaling_server_url` ใน [network_manager.gd](file:///c:/Users/fimlnwza/Downloads/AloneInTheDusk_Godot_2026-10-04/AloneInTheDusk/Scripts/network_manager.gd)

### ตัวเลือก B: Render.com (ฟรี 24/7)
1. ไปที่ [Render.com](https://render.com)
2. เลือก **New Web Service** เชื่อมต่อกับคลัง GitHub ของเกมนี้
3. ตั้งค่า:
   - **Root Directory:** `server`
   - **Build Command:** `npm install`
   - **Start Command:** `node signaling_server.js`
4. เมื่อ Deploy เสร็จ จะได้ URL เช่น `wss://alone-in-the-dusk.onrender.com`

---

## 3. ทำไมวิธีนี้ถึงแก้ปัญหา "Error code: 20" ได้ 100%?
* ในระบบเดิม เมื่อเล่นบนเว็บ Browser จะพยายามเปิดพอร์ต TCP/UDP เอง ซึ่งระบบความปลอดภัยของ Web ไม่อนุญาต จึงทำให้ขึ้น Error 20
* ระบบใหม่นี้ Browser ไม่ต้องเปิดพอร์ตเอง แต่เชื่อมต่อไปยัง Signaling Relay ผ่าน WebSocket ปกติ แล้วจับคู่ส่งข้อมูลผ่าน WebRTC P2P (Peer-to-Peer) ทำให้ทุกคนสร้างห้องได้จากทุกอุปกรณ์ครับ!
