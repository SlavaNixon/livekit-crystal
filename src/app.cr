require "kemal"
require "json"
require "base64"
require "openssl/hmac"

# --- Настройки (берутся из переменных окружения, см. docker-compose.yml) ---
API_KEY     = ENV.fetch("LIVEKIT_API_KEY", "devkey")
API_SECRET  = ENV.fetch("LIVEKIT_API_SECRET", "devsecretdevsecretdevsecretdevsecret")
# Адрес LiveKit, по которому подключается БРАУЗЕР (не адрес внутри docker-сети).
LIVEKIT_URL = ENV.fetch("LIVEKIT_PUBLIC_URL", "ws://localhost:7880")
TOKEN_TTL   = 3600 # секунд

# Разрешённые имя участника и название комнаты: буквы, цифры, _ - и пробел, до 32 символов.
SAFE_NAME = /\A[\p{L}\p{N}_\- ]{1,32}\z/

def b64(data : String | Bytes) : String
  Base64.urlsafe_encode(data, padding: false)
end

# LiveKit access token — это обычный JWT (HS256), подписанный API-секретом.
# Отдельная библиотека не нужна.
def build_token(identity : String, display_name : String, room : String) : String
  now = Time.utc.to_unix

  header = b64({alg: "HS256", typ: "JWT"}.to_json)
  payload = b64({
    iss:  API_KEY,
    sub:  identity,
    name: display_name,
    nbf:  now,
    exp:  now + TOKEN_TTL,
    video: {
      room:           room,
      roomJoin:       true,
      canPublish:     true,
      canSubscribe:   true,
      canPublishData: true,
    },
  }.to_json)

  signing_input = "#{header}.#{payload}"
  signature = b64(OpenSSL::HMAC.digest(:sha256, API_SECRET, signing_input))
  "#{signing_input}.#{signature}"
end

get "/" do |env|
  send_file env, "public/index.html"
end

# GET /api/token?name=Alice&room=test -> {"token": "...", "url": "ws://..."}
get "/api/token" do |env|
  env.response.content_type = "application/json"

  name = env.params.query["name"]?.try(&.strip) || ""
  room = env.params.query["room"]?.try(&.strip) || "test"

  unless SAFE_NAME.matches?(name) && SAFE_NAME.matches?(room)
    env.response.status_code = 400
    next({error: "Имя и комната: 1–32 символа (буквы, цифры, _ - и пробел)"}.to_json)
  end

  # Случайный суффикс, чтобы два человека с одинаковым именем не выкинули друг друга из комнаты.
  identity = "#{name}-#{Random::Secure.hex(3)}"

  {token: build_token(identity, name, room), url: LIVEKIT_URL}.to_json
end

if API_SECRET == "devsecretdevsecretdevsecretdevsecret"
  Log.warn { "Используется тестовый LIVEKIT_API_SECRET. Не запускайте так в продакшене." }
end

Kemal.config.port = ENV.fetch("PORT", "3000").to_i
Kemal.run
