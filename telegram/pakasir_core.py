"""
PAKASIR PAYMENT GATEWAY - CORE MODULE
Sesuai Dokumentasi Resmi: https://pakasir.com/p/docs
"""

import hashlib
import json
import os
import time
import asyncio
import aiohttp
import requests
import qrcode
from io import BytesIO
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

# ==================== KONFIGURASI ====================
# PAKAI PATH ABSOLUT KE /ETC/CONF/
PAKASIR_CONFIG_FILE = "/etc/conf/pakasir_config.json"
PAKASIR_TRX_FILE = "/etc/conf/pakasir_transaksi.json"

print(f"📁 PAKASIR CONFIG PATH: {PAKASIR_CONFIG_FILE}")
print(f"📁 PAKASIR TRX PATH: {PAKASIR_TRX_FILE}")

# CEK APAKAH FILE ADA
if os.path.exists(PAKASIR_CONFIG_FILE):
    print("✅ File pakasir_config.json ditemukan!")
else:
    print("⚠️ File pakasir_config.json TIDAK DITEMUKAN!")
    print("📝 Buat file di: /etc/conf/pakasir_config.json")

def load_pakasir_config():
    """Load konfigurasi Pakasir"""
    print(f"🔍 Mencari config di: {PAKASIR_CONFIG_FILE}")
    
    if not os.path.exists(PAKASIR_CONFIG_FILE):
        print(f"⚠️ Config tidak ditemukan, membuat default di: {PAKASIR_CONFIG_FILE}")
        default = {
            "api_key": "",
            "merchant_id": "",
            "base_url": "https://app.pakasir.com",
            "polling_interval": 5,
            "timeout_minutes": 10
        }
        # Buat direktori jika belum ada
        os.makedirs(os.path.dirname(PAKASIR_CONFIG_FILE), exist_ok=True)
        with open(PAKASIR_CONFIG_FILE, 'w') as f:
            json.dump(default, f, indent=2)
        print(f"✅ File default dibuat di: {PAKASIR_CONFIG_FILE}")
        print("⚠️ SILAKAN ISI API KEY DAN MERCHANT ID DI FILE TERSEBUT!")
        return default
    
    try:
        with open(PAKASIR_CONFIG_FILE, 'r') as f:
            config = json.load(f)
            api_key = config.get('api_key', '')
            merchant_id = config.get('merchant_id', '')
            print(f"✅ Config loaded: api_key={api_key[:10] if api_key else 'KOSONG'}..., merchant_id={merchant_id if merchant_id else 'KOSONG'}")
            
            if not api_key or not merchant_id:
                print("⚠️ PAKASIR: API Key atau Merchant ID belum diisi di /etc/conf/pakasir_config.json!")
            
            return config
    except json.JSONDecodeError as e:
        print(f"❌ JSON Error: {e}")
        print("⚠️ File config rusak! Perbaiki file /etc/conf/pakasir_config.json")
        return {"api_key": "", "merchant_id": "", "base_url": "https://app.pakasir.com", "polling_interval": 5, "timeout_minutes": 10}
    except Exception as e:
        print(f"❌ Error load config: {e}")
        return {"api_key": "", "merchant_id": "", "base_url": "https://app.pakasir.com", "polling_interval": 5, "timeout_minutes": 10}

def save_pakasir_config(config):
    """Simpan konfigurasi Pakasir"""
    try:
        os.makedirs(os.path.dirname(PAKASIR_CONFIG_FILE), exist_ok=True)
        with open(PAKASIR_CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        print("✅ Config saved")
    except Exception as e:
        print(f"❌ Gagal save config: {e}")

# ==================== DATABASE TRANSAKSI PAKASIR ====================
def load_pakasir_transactions():
    """Load semua transaksi Pakasir"""
    if not os.path.exists(PAKASIR_TRX_FILE):
        return {}
    try:
        with open(PAKASIR_TRX_FILE, 'r') as f:
            return json.load(f)
    except:
        return {}

def save_pakasir_transactions(data):
    try:
        os.makedirs(os.path.dirname(PAKASIR_TRX_FILE), exist_ok=True)
        with open(PAKASIR_TRX_FILE, 'w') as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        print(f"❌ Gagal save transaksi: {e}")

def save_pakasir_transaction(order_id: str, data: dict):
    """Simpan transaksi Pakasir"""
    trx = load_pakasir_transactions()
    trx[order_id] = data
    save_pakasir_transactions(trx)

def get_pakasir_transaction(order_id: str) -> Optional[dict]:
    """Ambil transaksi Pakasir berdasarkan order_id"""
    trx = load_pakasir_transactions()
    return trx.get(order_id)

def delete_pakasir_transaction(order_id: str):
    """Hapus transaksi Pakasir setelah selesai"""
    trx = load_pakasir_transactions()
    if order_id in trx:
        del trx[order_id]
        save_pakasir_transactions(trx)

# ==================== FUNGSI GENERATE QR CODE ====================
def generate_qr_image(data: str) -> Optional[BytesIO]:
    """
    Generate QR code dari string data
    Returns: BytesIO object berisi gambar QR
    """
    try:
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=16,
            border=8,
        )
        qr.add_data(data)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        
        bio = BytesIO()
        img.save(bio, format='PNG')
        bio.seek(0)
        return bio
    except Exception as e:
        print(f"❌ Gagal generate QR: {e}")
        return None

# ==================== API PAKASIR ====================
class PakasirClient:
    """Client untuk API Pakasir - Sesuai Docs"""
    
    def __init__(self):
        self.reload_config()
    
    def reload_config(self):
        """Reload konfigurasi dari file"""
        self.config = load_pakasir_config()
        self.api_key = self.config.get("api_key", "")
        self.merchant_id = self.config.get("merchant_id", "")
        self.base_url = self.config.get("base_url", "https://app.pakasir.com")
        self.polling_interval = self.config.get("polling_interval", 5)
        self.timeout_minutes = self.config.get("timeout_minutes", 10)
        
        print(f"🔄 Config loaded: merchant_id={self.merchant_id}, api_key={self.api_key[:10] if self.api_key else 'KOSONG'}...{self.api_key[-5:] if self.api_key else 'KOSONG'}")
        
        if not self.api_key or not self.merchant_id:
            print("⚠️ PAKASIR: API Key atau Merchant ID belum diisi!")
    
    async def create_invoice(self, amount: int, order_id: str, 
                             customer_name: str = "Customer", 
                             customer_email: str = "") -> Dict[str, Any]:
        """
        Membuat invoice QRIS di Pakasir
        Menggunakan REQUESTS (sync)
        """
        self.reload_config()
        
        if not self.api_key or not self.merchant_id:
            return {"success": False, "error": "Pakasir not configured"}
        
        url = f"{self.base_url}/api/transactioncreate/qris"
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "python-requests/2.31.0"
        }
        
        payload = {
            "project": self.merchant_id,
            "order_id": order_id,
            "amount": amount,
            "api_key": self.api_key
        }
        
        # 🔧 DEBUG
        print("="*70)
        print("🚀 PAKASIR CREATE INVOICE (BOT - REQUESTS)")
        print("="*70)
        print(f"📡 URL: {url}")
        print(f"📦 Payload: {json.dumps(payload, indent=2)}")
        print("="*70)
        
        try:
            response = requests.post(url, json=payload, headers=headers, timeout=30)
            
            print(f"📥 Status Code: {response.status_code}")
            print(f"📥 Raw Response: {response.text[:500]}...")
            print("="*70)
            
            if response.status_code == 200:
                data = response.json()
                payment = data.get("payment", {})
                payment_number = payment.get("payment_number", "")
                
                print(f"✅ SUCCESS!")
                print(f"   Project: {payment.get('project', 'N/A')}")
                print(f"   Order ID: {payment.get('order_id', 'N/A')}")
                print(f"   Amount: {payment.get('amount', 0)}")
                print(f"   Total Payment: {payment.get('total_payment', 0)}")
                print(f"   Fee: {payment.get('fee', 0)}")
                print(f"   Payment Number: {payment_number[:50] if payment_number else 'KOSONG'}...")
                print(f"   Is Sandbox: {payment.get('is_sandbox', False)}")
                print("="*70)
                
                # Simpan transaksi ke database lokal
                transaction_data = {
                    "order_id": order_id,
                    "amount": amount,
                    "status": "pending",
                    "payment_number": payment_number,
                    "payment_method": payment.get("payment_method", "qris"),
                    "total_payment": payment.get("total_payment", amount),
                    "fee": payment.get("fee", 0),
                    "expired_at": payment.get("expired_at", 
                        (datetime.now() + timedelta(minutes=self.timeout_minutes)).isoformat()),
                    "created_at": datetime.now().isoformat(),
                    "customer_name": customer_name,
                    "is_sandbox": payment.get("is_sandbox", False),
                    "raw_response": data
                }
                save_pakasir_transaction(order_id, transaction_data)
                print(f"✅ Transaksi disimpan ke database lokal: {order_id}")
                print("="*70)
                
                return {
                    "success": True,
                    "order_id": order_id,
                    "payment_number": payment_number,
                    "payment_method": payment.get("payment_method", "qris"),
                    "total_payment": payment.get("total_payment", amount),
                    "fee": payment.get("fee", 0),
                    "expired_time": self.timeout_minutes,
                    "is_sandbox": payment.get("is_sandbox", False),
                    "data": data
                }
            else:
                print(f"❌ ERROR: Status {response.status_code}")
                try:
                    error_data = response.json()
                    print(f"❌ Error Response: {json.dumps(error_data, indent=2)}")
                except:
                    print(f"❌ Raw Response: {response.text}")
                return {
                    "success": False,
                    "error": response.text[:200],
                    "code": response.status_code
                }
        except requests.exceptions.RequestException as e:
            print(f"❌ Request Error: {e}")
            return {"success": False, "error": f"Request error: {str(e)}"}
        except Exception as e:
            print(f"❌ Unexpected Error: {e}")
            import traceback
            traceback.print_exc()
            return {"success": False, "error": str(e)}
    
    async def check_status(self, order_id: str, amount: int = None) -> Dict[str, Any]:
        """
        Cek status transaksi di Pakasir
        Endpoint: GET /api/transactiondetail
        - order_id: ID transaksi
        - amount: total payment (opsional, jika tidak diberikan akan ambil dari data tersimpan)
        """
        self.reload_config()
        
        if not self.api_key or not self.merchant_id:
            return {"success": False, "error": "Pakasir not configured"}
        
        trx_local = get_pakasir_transaction(order_id)
        
        # Jika amount tidak diberikan, ambil dari data tersimpan
        if amount is None:
            if trx_local:
                # Prioritaskan total_payment jika ada
                amount = trx_local.get("total_payment", trx_local.get("amount", 0))
            else:
                amount = 0
        
        url = (
            f"{self.base_url}/api/transactiondetail"
            f"?project={self.merchant_id}"
            f"&amount={amount}"
            f"&order_id={order_id}"
            f"&api_key={self.api_key}"
        )
        
        print(f"🔍 Checking status: amount={amount}, order_id={order_id}")
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(url, timeout=30) as response:
                    data = await response.json()
                    print(f"📥 Status Response: {data}")
                    
                    if response.status == 200:
                        status = "pending"
                        if "payment" in data:
                            payment = data["payment"]
                            status = payment.get("status", "pending")
                            amount = payment.get("amount", amount)
                        elif "transaction" in data:
                            trx = data["transaction"]
                            status = trx.get("status", "pending")
                            amount = trx.get("amount", amount)
                        elif "status" in data:
                            status = data.get("status", "pending")
                        
                        if trx_local:
                            trx_local["status"] = status
                            trx_local["last_check"] = datetime.now().isoformat()
                            trx_local["raw_response"] = data
                            save_pakasir_transaction(order_id, trx_local)
                        
                        return {
                            "success": True,
                            "status": status,
                            "amount": amount,
                            "payment_time": data.get("paid_at"),
                            "data": data
                        }
                    else:
                        return {
                            "success": False,
                            "error": data.get("message", "Unknown error"),
                            "code": response.status,
                            "raw": data
                        }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    async def simulate_payment(self, order_id: str) -> Dict[str, Any]:
        """
        Simulasi pembayaran (hanya untuk SANDBOX)
        Endpoint: POST /api/paymentsimulation
        """
        self.reload_config()
        
        if not self.api_key or not self.merchant_id:
            return {"success": False, "error": "Pakasir not configured"}
        
        trx_local = get_pakasir_transaction(order_id)
        amount = trx_local.get("amount", 0) if trx_local else 0
        
        if amount == 0:
            return {"success": False, "error": "Amount not found"}
        
        url = f"{self.base_url}/api/paymentsimulation"
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json"
        }
        
        payload = {
            "project": self.merchant_id,
            "order_id": order_id,
            "amount": amount,
            "api_key": self.api_key
        }
        
        print(f"🔍 Simulating payment: {url}")
        print(f"📦 Payload: {payload}")
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(url, json=payload, headers=headers, timeout=30) as response:
                    data = await response.json()
                    print(f"📥 Simulation Response: {data}")
                    
                    if response.status == 200:
                        return {
                            "success": True,
                            "message": data.get("message", "Payment simulated"),
                            "data": data
                        }
                    else:
                        return {
                            "success": False,
                            "error": data.get("message", "Unknown error"),
                            "code": response.status,
                            "raw": data
                        }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    async def poll_payment(self, order_id: str, callback=None, bot=None, user_id=None):
        """
        Polling status pembayaran secara periodik
        """
        trx = get_pakasir_transaction(order_id)
        if not trx:
            return "not_found"
        
        amount = trx.get("amount", 0)
        max_attempts = (self.timeout_minutes * 60) // self.polling_interval
        
        for attempt in range(max_attempts):
            await asyncio.sleep(self.polling_interval)
            
            result = await self.check_status(order_id)
            
            if not result.get("success"):
                print(f"⚠️ Polling error untuk {order_id}: {result.get('error')}")
                continue
            
            status = result.get("status", "pending")
            
            if callback:
                await callback(order_id, status, result)
            
            if bot and user_id and status == "completed":
                try:
                    await bot.send_message(
                        chat_id=user_id,
                        text=f"""
✅ *PEMBAYARAN BERHASIL!*

💰 Nominal: Rp {amount:,.0f}
🆔 Order ID: `{order_id}`

💳 Saldo Anda telah bertambah!
Gunakan /start untuk melanjutkan belanja.
""",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    print(f"⚠️ Gagal kirim notifikasi ke user {user_id}: {e}")
            
            if status in ["completed", "expired", "failed"]:
                if status in ["completed", "expired"]:
                    delete_pakasir_transaction(order_id)
                return status
        
        trx = get_pakasir_transaction(order_id)
        if trx:
            trx["status"] = "timeout"
            save_pakasir_transaction(order_id, trx)
            delete_pakasir_transaction(order_id)
        
        return "timeout"

# ==================== CLASS WRAPPER ====================
class PakasirPayment:
    """Wrapper untuk integrasi Pakasir ke bot PPOB"""
    
    def __init__(self, bot=None):
        print("🔧 PakasirPayment initialized!")
        self.client = PakasirClient()
        self.bot = bot
        self.active_polls = {}
    
    async def create_deposit(self, user_id: int, amount: int, 
                            username: str = "Customer") -> Dict[str, Any]:
        """Membuat deposit via Pakasir QRIS"""
        # 🔧 PAKAI PREFIX TEST_ (SAMA KAYAK SCRIPT TEST)
        order_id = f"TRX_{int(time.time())}_{hashlib.md5(str(user_id).encode()).hexdigest()[:6]}"
        
        result = await self.client.create_invoice(
            amount=amount,
            order_id=order_id,
            customer_name=username
        )
        
        if result.get("success"):
            trx = get_pakasir_transaction(order_id)
            if trx:
                trx["user_id"] = user_id
                save_pakasir_transaction(order_id, trx)
        
        return result
    
    async def start_polling(self, order_id: str, user_id: int, 
                           on_complete=None, on_expired=None, on_failed=None):
        """Mulai polling untuk transaksi tertentu"""
        if order_id in self.active_polls:
            print(f"⚠️ Polling sudah berjalan untuk {order_id}")
            return
        
        self.active_polls[order_id] = True
        
        async def status_callback(oid, status, result):
            if status == "completed":
                trx = get_pakasir_transaction(oid)
                if trx:
                    amount = trx.get("amount", 0)
                    uid = trx.get("user_id")
                    
                    if uid:
                        if on_complete:
                            await on_complete(uid, amount, oid)
            elif status == "expired":
                if on_expired:
                    trx = get_pakasir_transaction(oid)
                    if trx:
                        await on_expired(trx.get("user_id"), oid)
            elif status == "failed":
                if on_failed:
                    trx = get_pakasir_transaction(oid)
                    if trx:
                        await on_failed(trx.get("user_id"), oid)
        
        final_status = await self.client.poll_payment(
            order_id=order_id,
            callback=status_callback,
            bot=self.bot,
            user_id=user_id
        )
        
        if order_id in self.active_polls:
            del self.active_polls[order_id]
        
        return final_status
    
    async def check_status(self, order_id: str, amount: int = None) -> Dict[str, Any]:
        """Cek status transaksi"""
        return await self.client.check_status(order_id, amount=amount)
    
    async def simulate_payment(self, order_id: str) -> Dict[str, Any]:
        """Simulasi pembayaran (hanya untuk SANDBOX)"""
        return await self.client.simulate_payment(order_id)
    
    def get_transaction(self, order_id: str) -> Optional[dict]:
        """Ambil data transaksi dari database lokal"""
        return get_pakasir_transaction(order_id)

# ==================== FUNGSI GENERATE KEYBOARD ====================
def generate_deposit_keyboard(order_id: str):
    """Generate keyboard untuk deposit (tanpa tombol lihat QRIS)"""
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup
    
    keyboard = [
        [InlineKeyboardButton("🔄 CEK STATUS", callback_data=f"cek_payment_{order_id}")],
        [InlineKeyboardButton("❌ BATAL", callback_data=f"batal_deposit_{order_id}")]
    ]
    return InlineKeyboardMarkup(keyboard)

# ==================== INISIALISASI GLOBAL ====================
_pakasir_payment = None

def init_pakasir(bot=None):
    global _pakasir_payment
    _pakasir_payment = PakasirPayment(bot)
    print(f"🔧 PakasirPayment initialized: {_pakasir_payment}")
    return _pakasir_payment

def get_pakasir():
    """Ambil instance PakasirPayment"""
    global _pakasir_payment
    if _pakasir_payment is None:
        print("⚠️ PakasirPayment belum diinisialisasi!")
    return _pakasir_payment