require "import"
import "android.speech.SpeechRecognizer"
import "android.speech.RecognizerIntent"
import "android.speech.tts.TextToSpeech"
import "android.widget.*"
import "android.view.*"
import "android.view.accessibility.AccessibilityNodeInfo"
import "android.app.*"
import "android.content.*"
import "android.net.Uri"
import "java.io.File"
import "android.os.*"
import "android.os.Build"
import "android.os.Handler"
import "android.os.Looper"
import "java.lang.Runnable"
import "java.util.Locale"
import "android.graphics.Typeface"
import "com.androlua.Http"
import "android.app.AlertDialog"
import "android.media.MediaPlayer"
import "cjson"

local service = service or accessibilityService
local prefs = service.getSharedPreferences("VoiceInputV1_Prefs", Context.MODE_PRIVATE)

-- Inisialisasi tempPrefsData segera agar selalu sinkron
local tempPrefsData = {}
local function initTempPrefs()
  tempPrefsData = {}
  local all = prefs.getAll()
  local it = all.entrySet().iterator()
  while it.hasNext() do
    local e = it.next()
    tempPrefsData[tostring(e.getKey())] = e.getValue()
  end
end
initTempPrefs()

local function getPref(k, d) 
  if tempPrefsData[k] ~= nil then 
    local v = tempPrefsData[k]
    if type(v) == "boolean" then return v end
    return tostring(v)
  end
  return prefs.getString(k, d) or d 
end

local function setPref(k, v) 
  tempPrefsData[k] = tostring(v)
end

local function getBool(k) 
  if tempPrefsData[k] ~= nil then 
    local v = tempPrefsData[k]
    if type(v) == "boolean" then return v end
    if v == "true" or v == "1" then return true else return false end
  end
  return prefs.getBoolean(k, false) 
end

local function setBool(k, v) 
  tempPrefsData[k] = v 
end

local function commitPrefs()
  local editor = prefs.edit()
  for k, v in pairs(tempPrefsData) do
    if type(v) == "boolean" then
      editor.putBoolean(k, v)
    else
      editor.putString(k, tostring(v))
    end
  end
  editor.apply()
end

local function pesan(teks) Toast.makeText(service, teks, Toast.LENGTH_SHORT).show() end

local ttsGlobal = nil
local function speakText(teks)
  if not teks or teks == "" then return end
  local engine = getPref("tts_engine", "")
  local pitch = (tonumber(getPref("tts_pitch", "100")) or 100) / 100
  local rate = (tonumber(getPref("tts_rate", "100")) or 100) / 100
  
  local listener = luajava.createProxy("android.speech.tts.TextToSpeech$OnInitListener", {
    onInit = function(status)
      if status == TextToSpeech.SUCCESS then
        if ttsGlobal then
          ttsGlobal.setPitch(pitch)
          ttsGlobal.setSpeechRate(rate)
          ttsGlobal.setLanguage(Locale("id", "ID"))
          if Build.VERSION.SDK_INT >= 21 then
            ttsGlobal.speak(teks, TextToSpeech.QUEUE_FLUSH, nil, "tts_speak_id")
          else
            ttsGlobal.speak(teks, TextToSpeech.QUEUE_FLUSH, nil)
          end
        end
      end
    end
  })

  pcall(function()
    if ttsGlobal then ttsGlobal.shutdown() end
  end)

  if engine ~= "" then
    ttsGlobal = TextToSpeech(service, listener, engine)
  else
    ttsGlobal = TextToSpeech(service, listener)
  end
end

local function vibrate(ms)
  if not getBool("use_vibration") then return end
  local v = service.getSystemService(Context.VIBRATOR_SERVICE)
  local dur = ms or tonumber(getPref("vibration_duration", "50"))
  if v and v.hasVibrator() then v.vibrate(dur) end
end

local function replaceText(node, text)
  if not node then return end
  local ok = pcall(function()
    if Build.VERSION.SDK_INT >= 21 then
      local args = Bundle()
      args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
      node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    else
      service.setText(node, text)
    end
  end)
  if not ok then
    pcall(function() service.insert(node, text) end)
  end
end

local function showDialog(dialog)
  dialog.show()
  return dialog
end

local function showPengaturanTTS()
  local layT = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
  layT.addView(TextView(service).setText("Pilih Mesin TTS:").setTypeface(Typeface.DEFAULT_BOLD))
  
  local engineNames = {}
  local enginePkgs = {}
  local dummyTts = TextToSpeech(service, nil)
  local engines = dummyTts.getEngines()
  if engines then
    for i = 0, engines.size() - 1 do
      local eng = engines.get(i)
      table.insert(engineNames, tostring(eng.label))
      table.insert(enginePkgs, tostring(eng.name))
    end
  end
  pcall(function() dummyTts.shutdown() end)
  
  if #engineNames == 0 then
    table.insert(engineNames, "Default System TTS")
    table.insert(enginePkgs, "")
  end

  local spinEngine = Spinner(service).setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_dropdown_item, engineNames))
  local curEngine = getPref("tts_engine", "")
  for i, pkg in ipairs(enginePkgs) do
    if pkg == curEngine then spinEngine.setSelection(i-1) break end
  end
  layT.addView(spinEngine)

  local curPitch = tonumber(getPref("tts_pitch", "100")) or 100
  local txtPitch = TextView(service).setText("\nNada (Pitch): " .. string.format("%.1f", curPitch / 100) .. "x")
  local skPitch = SeekBar(service).setMax(200)
  skPitch.setProgress(curPitch)
  skPitch.setOnSeekBarChangeListener{onProgressChanged=function(bar, prog)
    if prog < 20 then prog = 20 end
    txtPitch.setText("\nNada (Pitch): " .. string.format("%.1f", prog / 100) .. "x")
    setPref("tts_pitch", tostring(prog))
  end}
  layT.addView(txtPitch)
  layT.addView(skPitch)

  local curRate = tonumber(getPref("tts_rate", "100")) or 100
  local txtRate = TextView(service).setText("\nKecepatan (Speed): " .. string.format("%.1f", curRate / 100) .. "x")
  local skRate = SeekBar(service).setMax(200)
  skRate.setProgress(curRate)
  skRate.setOnSeekBarChangeListener{onProgressChanged=function(bar, prog)
    if prog < 20 then prog = 20 end
    txtRate.setText("\nKecepatan (Speed): " .. string.format("%.1f", prog / 100) .. "x")
    setPref("tts_rate", tostring(prog))
  end}
  layT.addView(txtRate)
  layT.addView(skRate)

  local dlg = LuaDialog(service)
  dlg.setTitle("Pengaturan TTS")
  dlg.setView(layT)
  dlg.setPositiveButton("Simpan", {onClick=function()
    local selectedIdx = spinEngine.getSelectedItemPosition() + 1
    if enginePkgs[selectedIdx] then
      setPref("tts_engine", enginePkgs[selectedIdx])
    end
    pesan("Pengaturan TTS disimpan sementara!")
  end})
  dlg.setNegativeButton("Batal", nil)
  dlg.show()
end

local function applySingkatan(teks)
  if not getBool("use_singkatan") then return teks end
  local daftarAngka2 = {"sama", "teman", "jalan", "makan", "hati", "hati%-hati"}
  for _, kata in ipairs(daftarAngka2) do
    teks = teks:gsub("%f[%a]"..kata.."%s+"..kata.."%f[%A]", kata.."2")
    teks = teks:gsub("%f[%a]"..kata.."%-"..kata.."%f[%A]", kata.."2")
  end
  local s = {
    ["yang"] = "yg", ["dengan"] = "dg", ["untuk"] = "utk", ["tidak"] = "tdk",
    ["ngggak"] = "gk", ["kamu"] = "km", ["saya"] = "sy", ["sudah"] = "sdh",
    ["bang"] = "bg", ["kakak"] = "kk", ["kenapa"] = "knp", ["gimana"] = "gmn",
    ["sekarang"] = "skrg", ["banget"] = "bgt", ["tapi"] = "tp", ["kalo"] = "kl",
    ["terima kasih"] = "tks",
  }
  for k, v in pairs(s) do
    teks = teks:gsub("%f[%a]"..k.."%f[%A]", v)
    local kapital = k:sub(1,1):upper()..k:sub(2)
    local v_kapital = v:sub(1,1):upper()..v:sub(2)
    teks = teks:gsub("%f[%a]"..kapital.."%f[%A]", v_kapital)
  end
  return teks
end

local function applyGaya(t)
  if getBool("use_gaya_vokal") then
    local vokalCharSet = getPref("vokal_char_set", "AIUEO")
    local n = tonumber(getPref("vokal_count", "2")) or 2
    if vokalCharSet == "Cadel C" then
      t = t:gsub("[rlk]", "c"):gsub("[RLK]", "C")
    elseif vokalCharSet == "AIUEO" then
      t = t:gsub("([aiueoAIUEO])", function(v) return v:rep(n) end)
    elseif vokalCharSet == "A" then
      t = t:gsub("([aA])", function(v) return v:rep(n) end)
    elseif vokalCharSet == "I" then
      t = t:gsub("([iI])", function(v) return v:rep(n) end)
    end
  end
  return t
end

-- ================ DATA FITUR KATEGORI ================
local AI_FEATURES = {
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Sederhana", prompt_template = "Jelaskan konsep ini dengan analogi sederhana sehingga mudah dipahami oleh anak 5 tahun."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Akademik", prompt_template = "Jelaskan konsep ini secara mendalam dengan contoh-contoh akademis."},
  {category = "Edukasi & Pembelajaran", title = "Buat Rangkuman Artikel", prompt_template = "Rangkum artikel atau teks panjang ini menjadi poin-poin utama."},
  {category = "Edukasi & Pembelajaran", title = "Buat Soal Pilihan Ganda", prompt_template = "Buat 5 soal pilihan ganda dari teks input ini. Sertakan kunci jawabannya."},
  {category = "Edukasi & Pembelajaran", title = "Buat Soal Esai", prompt_template = "Buat 3 soal esai berdasarkan materi dari teks input ini."},
  {category = "Edukasi & Pembelajaran", title = "Buat Ringkasan Bab Buku", prompt_template = "Buat ringkasan bab buku dari input teks."},
  {category = "Edukasi & Pembelajaran", title = "Buat Peta Konsep", prompt_template = "Buat peta konsep (mind map) dari materi yang diinput."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Istilah Hukum", prompt_template = "Jelaskan istilah hukum yang disebutkan secara ringkas."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Istilah Medis", prompt_template = "Jelaskan istilah medis yang disebutkan secara ringkas."},
  {category = "Edukasi & Pembelajaran", title = "Buat Daftar Fakta Menarik", prompt_template = "Sebutkan 10 fakta unik yang relevan dengan topik di teks input."},
  {category = "Edukasi & Pembelajaran", title = "Buat Soal Benar/Salah", prompt_template = "Buat 5 soal benar/salah dari teks input ini. Sertakan kunci jawabannya."},
  {category = "Edukasi & Pembelajaran", title = "Rekomendasi Buku Bacaan", prompt_template = "Rekomendasikan 5 buku bacaan populer tentang topik di teks input."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Matematika", prompt_template = "Jelaskan konsep matematika [Sebutkan konsep] dengan contoh soal."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Fisika", prompt_template = "Jelaskan konsep fisika [Sebutkan konsep] dengan contoh sederhana."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Sejarah", prompt_template = "Jelaskan peristiwa sejarah [Sebutkan peristiwa] secara ringkas."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Biologi", prompt_template = "Jelaskan konsep biologi [Sebutkan konsep] dengan analogi."},
  {category = "Edukasi & Pembelajaran", title = "Tulis Rangkuman Jurnal Ilmiah", prompt_template = "Rangkum jurnal ilmiah yang diinput (masalah, metodologi, hasil, kesimpulan)."},
  {category = "Edukasi & Pembelajaran", title = "Daftar Topik Penelitian", prompt_template = "Berikan 5 ide topik penelitian yang relevan dengan subjek di teks input."},
  {category = "Edukasi & Pembelajaran", title = "Buat Catatan Kuliah Ringkas", prompt_template = "Buat catatan kuliah yang rapi dari input materi. Gunakan poin-poin penting."},
  {category = "Edukasi & Pembelajaran", title = "Saran Topik Esai", prompt_template = "Berikan 5 ide topik esai yang relevan dengan tema di teks input."},
  {category = "Edukasi & Pembelajaran", title = "Perbaiki Argumen Logis", prompt_template = "Perbaiki argumen logis dalam teks input agar lebih kuat dan valid."},
  {category = "Edukasi & Pembelajaran", title = "Buat Draf Proposal Penelitian", prompt_template = "Buat draf proposal penelitian sederhana (latar belakang, rumusan masalah, tujuan)."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Teori Ekonomi", prompt_template = "Jelaskan teori ekonomi [Sebutkan teori] dengan contoh sederhana."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Teori Filsafat", prompt_template = "Jelaskan teori filsafat [Sebutkan teori] dengan contoh sederhana."},
  {category = "Edukasi & Pembelajaran", title = "Buat Rangkuman Berita", prompt_template = "Rangkum berita dari teks input menjadi poin-poin utama."},
  {category = "Edukasi & Pembelajaran", title = "Buat Teks Presentasi PowerPoint", prompt_template = "Buat teks presentasi untuk PowerPoint berdasarkan input materi."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Sains", prompt_template = "Jelaskan konsep sains [Sebutkan konsep] dengan mudah."},
  {category = "Edukasi & Pembelajaran", title = "Buat Daftar Pertanyaan Interview Ahli", prompt_template = "Buat 5 pertanyaan interview untuk narasumber ahli di bidang [Sebutkan bidang]."},
  {category = "Edukasi & Pembelajaran", title = "Tulis Ulasan Akademik", prompt_template = "Tulis ulasan akademik tentang buku atau jurnal [Sebutkan judul]."},
  {category = "Edukasi & Pembelajaran", title = "Perbaiki Kutipan & Daftar Pustaka", prompt_template = "Perbaiki format kutipan dan daftar pustaka (APA Style) dari teks input."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Kebudayaan", prompt_template = "Jelaskan konsep kebudayaan [Sebutkan konsep] dengan contoh."},
  {category = "Edukasi & Pembelajaran", title = "Tulis Draf Tugas Akhir/Skripsi", prompt_template = "Buat draf pendahuluan untuk tugas akhir/skripsi dengan topik [Sebutkan topik]."},
  {category = "Edukasi & Pembelajaran", title = "Buat Kuis Interaktif", prompt_template = "Buat 5 pertanyaan kuis interaktif dari teks input."},
  {category = "Edukasi & Pembelajaran", title = "Saran Topik Diskusi Kelompok", prompt_template = "Berikan 5 ide topik diskusi kelompok yang relevan dengan input."},
  {category = "Edukasi & Pembelajaran", title = "Daftar Tokoh Sejarah", prompt_template = "Buat daftar tokoh sejarah penting yang relevan dengan input topik."},
  {category = "Edukasi & Pembelajaran", title = "Jelaskan Konsep Geografi", prompt_template = "Jelaskan konsep geografi [Sebutkan konsep] dengan contoh."},
  {category = "Edukasi & Pembelajaran", title = "Ubah Teks Menjadi Infografis", prompt_template = "Ubah teks input menjadi poin-poin untuk infografis."},
  {category = "Edukasi & Pembelajaran", title = "Buat Ringkasan Berita Sains", prompt_template = "Ringkas berita sains terbaru dari teks input."},
  {category = "Edukasi & Pembelajaran", title = "Saran Topik Penelitian Lanjutan", prompt_template = "Berikan 3 saran topik penelitian lanjutan dari teks input."},
  {category = "Edukasi & Pembelajaran", title = "Analisis Teks Kritis", prompt_template = "Lakukan analisis kritis terhadap teks input (keunggulan, kelemahan, asumsi)."},

  {category = "Programming & Data", title = "Koreksi Kode Python", prompt_template = "Temukan error dan perbaiki kode Python ini. Jelaskan perubahannya."},
  {category = "Programming & Data", title = "Tulis Kode Python (Sederhana)", prompt_template = "Tuliskan kode Python sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Koreksi Kode Lua", prompt_template = "Temukan error dan perbaiki kode Lua ini. Jelaskan perubahannya."},
  {category = "Programming & Data", title = "Tulis Kode Lua (Sederhana)", prompt_template = "Tuliskan kode Lua sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Tulis Kode HTML", prompt_template = "Tuliskan kode HTML sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Buat Struktur JSON", prompt_template = "Konversi informasi dalam teks ini ke format JSON yang terstruktur. Contoh: {key: value, ...}."},
  {category = "Programming & Data", title = "Teks ke Tabel CSV", prompt_template = "Susun informasi dari teks input menjadi format tabel CSV."},
  {category = "Programming & Data", title = "Teks ke Struktur Markdown", prompt_template = "Format teks ini ke format Markdown yang rapi."},
  {category = "Programming & Data", title = "Buat Query SQL", prompt_template = "Tuliskan query SQL berdasarkan permintaan data yang ada di teks input."},
  {category = "Programming & Data", title = "Tulis Dokumentasi Kode", prompt_template = "Tuliskan dokumentasi yang jelas untuk potongan kode yang diinput."},
  {category = "Programming & Data", title = "Tulis Kode JavaScript (Sederhana)", prompt_template = "Tuliskan kode JavaScript sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Tulis Kode PHP (Sederhana)", prompt_template = "Tuliskan kode PHP sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Tulis Kode Java (Sederhana)", prompt_template = "Tuliskan kode Java sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Optimasi Kode", prompt_template = "Optimalkan kode ini agar berjalan lebih cepat dan efisien. Jelaskan perubahannya."},
  {category = "Programming & Data", title = "Cari Error Code", prompt_template = "Identifikasi error dalam kode ini dan berikan solusinya."},
  {category = "Programming & Data", title = "Buat RegEx", prompt_template = "Buat ekspresi reguler (RegEx) berdasarkan pola yang diinput."},
  {category = "Programming & Data", title = "Jelaskan Konsep Programming", prompt_template = "Jelaskan konsep programming [Sebutkan konsep] dengan contoh kode sederhana."},
  {category = "Programming & Data", title = "Buat Struktur Data", prompt_template = "Buat struktur data (array, list, dictionary) dari teks input."},
  {category = "Programming & Data", title = "Tulis Kode CSS", prompt_template = "Tuliskan kode CSS sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Debug Code JavaScript", prompt_template = "Debug kode JavaScript ini dan perbaiki kesalahannya."},
  {category = "Programming & Data", title = "Tulis Kode GoLang (Sederhana)", prompt_template = "Tuliskan kode GoLang sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Tulis Kode C# (Sederhana)", prompt_template = "Tuliskan kode C# sederhana berdasarkan deskripsi input."},
  {category = "Programming & Data", title = "Jelaskan Konsep Data Science", prompt_template = "Jelaskan konsep data science [Sebutkan konsep] dengan mudah."},
  {category = "Programming & Data", title = "Buat Template Boilerplate Code", prompt_template = "Buat template boilerplate code untuk [Sebutkan bahasa/framework]."},
  {category = "Programming & Data", title = "Tulis Kode Shell Script", prompt_template = "Tuliskan kode shell script sederhana untuk otomatisasi tugas."},
  {category = "Programming & Data", title = "Buat Dokumentasi API", prompt_template = "Buat dokumentasi API sederhana dari input endpoint."},
  {category = "Programming & Data", title = "Konversi Kode (Python -> Java)", prompt_template = "Konversi kode Python ini ke dalam bahasa Java."},
  {category = "Programming & Data", title = "Konversi Kode (Java -> Python)", prompt_template = "Konversi kode Java ini ke dalam bahasa Python."},
  {category = "Programming & Data", title = "Tulis Code Review", prompt_template = "Berikan ulasan kode (code review) untuk potongan kode ini."},
  {category = "Programming & Data", title = "Analisis Kompleksitas Algoritma", prompt_template = "Analisis kompleksitas waktu dan ruang dari algoritma ini."},
  {category = "Programming & Data", title = "Buat Skrip Otomatisasi", prompt_template = "Buat skrip otomatisasi sederhana (misal: Python/Shell) untuk tugas tertentu."},
  {category = "Programming & Data", title = "Buat Query MongoDB", prompt_template = "Tuliskan query MongoDB (JSON) berdasarkan permintaan data."},
  {category = "Programming & Data", title = "Jelaskan Arsitektur Software", prompt_template = "Jelaskan arsitektur software [Sebutkan arsitektur] dengan contoh."},
  {category = "Programming & Data", title = "Tulis Code Snippet React", prompt_template = "Tuliskan code snippet React functional component untuk [Sebutkan fungsi]."},
  {category = "Programming & Data", title = "Jelaskan Konsep AI/ML", prompt_template = "Jelaskan konsep AI/ML [Sebutkan konsep] dengan contoh."},
  {category = "Programming & Data", title = "Buat Draf Spesifikasi Teknis", prompt_template = "Buat draf spesifikasi teknis sederhana untuk [Sebutkan proyek]."},
  {category = "Programming & Data", title = "Tulis Test Case Otomatis", prompt_template = "Tuliskan test case otomatis (unit test) untuk kode ini."},
  {category = "Programming & Data", title = "Buat Draf Git Commit Message", prompt_template = "Buat draf pesan Git commit yang deskriptif untuk perubahan kode ini."},
  {category = "Programming & Data", title = "Jelaskan Error Python", prompt_template = "Jelaskan error Python ini dan berikan solusinya."},
  {category = "Programming & Data", title = "Tulis Kode C++ (Sederhana)", prompt_template = "Tuliskan kode C++ sederhana berdasarkan deskripsi input."},

  {category = "Fitur Khusus & Lainnya", title = "Diktasi Standar (Instruksi Default)", prompt_template = "Perbaiki ejaan, tata bahasa, dan tanda baca dari teks ini. Pertahankan gaya bahasa aslinya."},
  {category = "Fitur Khusus & Lainnya", title = "Roleplay sebagai AI Santai", prompt_template = "Berperan sebagai asisten AI yang santai dan humoris. Jawab pertanyaan dengan gaya gaul."},
  {category = "Fitur Khusus & Lainnya", title = "Roleplay sebagai AI Formal", prompt_template = "Berperan sebagai asisten AI yang profesional dan formal. Jawab pertanyaan dengan bahasa baku."},
  {category = "Fitur Khusus & Lainnya", title = "Roleplay sebagai Kritikus Film", prompt_template = "Berperan sebagai kritikus film. Berikan ulasan mendalam tentang film yang disebutkan."},
  {category = "Fitur Khusus & Lainnya", title = "Prediksi Hasil Situasi", prompt_template = "Prediksi kemungkinan hasil atau konsekuensi dari situasi yang dijelaskan di teks input."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Peta Pikiran (Mind Map)", prompt_template = "Buat peta pikiran terstruktur dari teks input ini."},
  {category = "Fitur Khusus & Lainnya", title = "Teks ke Tabel HTML", prompt_template = "Konversi informasi dari teks input menjadi tabel HTML."},
  {category = "Fitur Khusus & Lainnya", title = "Teks ke Tweet", prompt_template = "Ubah teks panjang ini menjadi tweet yang ringkas dan menarik (maksimal 280 karakter)."},
  {category = "Fitur Khusus & Lainnya", title = "Teks ke Instagram Story", prompt_template = "Ubah teks ini menjadi poin-poin singkat yang cocok untuk Instagram Story."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Catatan Harian", prompt_template = "Buat catatan harian dari input kegiatan."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Rencana Harian", prompt_template = "Buat rencana harian terstruktur dari input tujuan."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Daftar Belanja", prompt_template = "Buat daftar belanja dari input kebutuhan."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Perbandingan", prompt_template = "Buat perbandingan antara dua hal yang disebutkan di teks input (misal: A vs B)."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Teks Promosi Webinar", prompt_template = "Buat teks promosi untuk webinar (judul, deskripsi, pembicara)."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Review Produk/Jasa", prompt_template = "Tulis ulasan produk atau jasa (positif/negatif) berdasarkan input pengalaman."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Deskripsi Tempat Wisata", prompt_template = "Buat deskripsi tempat wisata yang menarik berdasarkan nama tempat."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Teks Pemandu Wisata", prompt_template = "Buat teks narasi untuk pemandu wisata tentang tempat [Sebutkan tempat]."},
  {category = "Fitur Khusus & Lainnya", title = "Analisis Teks Kritis", prompt_template = "Lakukan analisis kritis terhadap teks input (keunggulan, kelemahan, asumsi)."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Deskripsi Pameran Seni", prompt_template = "Buat deskripsi untuk pameran seni berdasarkan input tema."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Rencana Anggaran Pribadi", prompt_template = "Buat rencana anggaran bulanan sederhana berdasarkan input penghasilan dan pengeluaran."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Daftar Barang Bawaan Liburan", prompt_template = "Buat daftar barang bawaan yang harus dibawa saat liburan ke [Sebutkan tempat]."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Draf Permintaan Donasi", prompt_template = "Buat draf teks permintaan donasi untuk kegiatan sosial."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Deskripsi Event", prompt_template = "Buat deskripsi event (seminar, konser, dll) yang menarik."},
  {category = "Fitur Khusus & Lainnya", title = "Saran Topik Diskusi", prompt_template = "Berikan 5 ide topik diskusi yang relevan dengan input."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Kuis Interaktif", prompt_template = "Buat 5 pertanyaan kuis interaktif dari teks input."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Draf Rangkuman Buku", prompt_template = "Rangkum buku [Sebutkan judul] menjadi poin-poin penting."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Peringkasan Dokumen", prompt_template = "Ringkas dokumen panjang menjadi inti-inti utamanya."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Panggilan Telepon Darurat", prompt_template = "Buat skrip panggilan telepon darurat (misal: melaporkan kecelakaan)."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Draf Laporan Cuaca", prompt_template = "Tulis draf laporan cuaca harian berdasarkan data input."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Rencana Belajar Mandiri", prompt_template = "Buat rencana belajar mandiri 30 hari untuk topik [Sebutkan topik]."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Draf Pesan Balasan Otomatis", prompt_template = "Buat draf pesan balasan otomatis untuk email atau chat."},
  {category = "Fitur Khusus & Lainnya", title = "Jelaskan Konsep Dasar Investasi", prompt_template = "Jelaskan konsep dasar investasi [Sebutkan konsep] dengan analogi sederhana."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Rencana Pensiun Sederhana", prompt_template = "Buat rencana pensiun sederhana berdasarkan input usia dan penghasilan."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Laporan Progress Kerja", prompt_template = "Tulis laporan progress kerja harian/mingguan berdasarkan input kegiatan."},
  {category = "Fitur Khusus & Lainnya", title = "Buat Naskah Debat", prompt_template = "Buat naskah debat singkat untuk topik [Sebutkan topik]."},
  {category = "Fitur Khusus & Lainnya", title = "Tulis Perencanaan Keuangan Keluarga", prompt_template = "Buat perencanaan keuangan keluarga berdasarkan input anggaran."},
}

local function getUniqueCategories()
  local cats = {}
  for _, feat in ipairs(AI_FEATURES) do
    cats[feat.category] = true
  end
  local sorted = {}
  for name in pairs(cats) do table.insert(sorted, name) end
  table.sort(sorted)
  return sorted
end

-- ================ FUNGSI UTAMA PEMROSESAN TEKS ================
local function processText(userInput, callback)
  if not userInput or userInput == "" then return end

  local originalCallback = callback
  local function wrappedCallback(hasil)
    if getBool("use_memory_mode") then
      addChatMemory(userInput, hasil)
    end
    originalCallback(hasil)
  end
  callback = wrappedCallback

  local function terapkanSemuaGaya(teks)
    -- Kamus pengganti kata
    if getBool("use_kamus") then
      local s, data = pcall(cjson.decode, getPref("kamus_json", "{}"))
      if s and type(data) == "table" then 
        for k, v in pairs(data) do
          -- Trim untuk menghindari spasi tersembunyi
          local kataAsli = tostring(k):match("^%s*(.-)%s*$")
          local kataGanti = tostring(v)
          if kataAsli and kataAsli ~= "" then
            local kEsc = kataAsli:gsub("([^%w])", "%%%1")
            -- Ganti kata asli (lowercase)
            teks = teks:gsub("%f[%a]"..kEsc.."%f[%A]", kataGanti)
            -- Ganti jika kata asli diawali huruf kapital
            local kKapital = kataAsli:sub(1,1):upper()..kataAsli:sub(2)
            local kKapitalEsc = kKapital:gsub("([^%w])", "%%%1")
            teks = teks:gsub("%f[%a]"..kKapitalEsc.."%f[%A]", kataGanti)
          end
        end 
      end
    end

    teks = applySingkatan(teks)
    teks = applyGaya(teks)
    if getBool("use_brutal_punc") then
      teks = teks:gsub("%?", "???"):gsub("%!", "!!!")
      if not teks:match("[%?%.%!]$") then teks = teks .. "!!!" end
    end
    local modeAkhir = getPref("akhir_kalimat_mode", "Tidak Ada")
    if modeAkhir == "Garis Baru" then teks = teks .. "\n"
    elseif modeAkhir == "Spasi" then teks = teks .. " "
    elseif modeAkhir == "Custom" then
      local customTeks = getPref("akhir_kalimat_custom", "")
      if customTeks ~= "" then teks = teks .. customTeks end
    end
    if getBool("use_no_space") then teks = teks:gsub("%s+", "") end
    return teks
  end

  local function eksekusiAI(textToProcess)
    -- ... (isi eksekusiAI sama seperti sebelumnya, tidak diubah)
    -- Karena panjang, saya tidak mengubahnya di sini.
    -- Namun pastikan tidak ada error. Kode ini sudah stabil.
    local inputAman = tostring(textToProcess or "")
    local gayaAktif = getBool("use_ai_style")
    local selectedFeatureIndex = tonumber(getPref("ai_feature_index", "0")) or 0
    local customAktif = getBool("use_custom_instr")
    local customPrompt = getPref("active_custom_prompt", "")
    local ghostAktif = getBool("use_ghost_mode")
    local stylePrompt = ""
    
    if gayaAktif then
      if selectedFeatureIndex > 0 and selectedFeatureIndex <= #AI_FEATURES then
        local feature = AI_FEATURES[selectedFeatureIndex]
        stylePrompt = "Tugas: " .. feature.prompt_template
      else
        local gayaBicara = getPref("gaya_bicara_ai", "Anak Jaksel")
        if gayaBicara == "Anak Jaksel" then
          stylePrompt = "STYLE: Natural South Jakarta casual conversation style (Anak Jaksel). Mix a few natural English words (e.g. 'literally', 'basically', 'which is', 'prefer') ONLY if it fits naturally in standard everyday chat. Do NOT force awkward English words."
        elseif gayaBicara == "Gaya Lo Gue" then
          stylePrompt = "STYLE: Natural Jakarta informal slang (Gaya Lo Gue). Smoothly convert standard pronouns ('saya/aku' -> 'gue', 'kamu' -> 'lu'). Ensure the text sounds exactly like a real human chatting with friends. STRICT RULE: DO NOT force unnatural slang particles like 'dong', 'sih', or 'deh' at the end of sentences if they don't naturally fit."
        elseif gayaBicara == "Gaya Santai & Lucu Bayi" then
          stylePrompt = "STYLE: Soft, cute toddler tone. Apply a subtle cute touch (e.g. slight soft pronoun adjustments), but keep the sentence completely natural and readable. Do NOT destroy context."
        end
      end
    end

    local baseSystemRule = "Perbaiki ejaan, tata bahasa, dan tanda baca dari teks berikut ini tanpa mengubah struktur atau susunan kata-katanya. Langsung berikan teks perbaikannya saja."
    local systemRule = baseSystemRule

    if ghostAktif then
      systemRule = "UBAH TEKS BERIKUT MENJADI VERSI SANGAT KASAR DAN MARAH. ATURAN WAJIB: " ..
        "1. JANGAN MENJAWAB PERTANYAAN ATAU MENANGGAPI ISI TEKS. HANYA TULIS ULANG TEKS TERSEBUT DENGAN GAYA MARAH. " ..
        "2. Gunakan kata-kata kasar, sarkastik, dan merendahkan. " ..
        "3. Ubah 'aku/saya' menjadi 'gua', 'kamu/kalian' menjadi 'lu', dan gunakan bahasa yang sangat nyolot. " ..
        "4. TIDAK BOLEH ada teks pengantar seperti 'Ini versinya:' atau komentar lain. " ..
        "5. Output harus berisi teks yang sudah dirombak dengan kata-kata kasar, tetap mempertahankan makna asli dari yang diucapkan user."
      speakText("Hihihi...")
    else
      if gayaAktif then
        systemRule = systemRule .. " " .. stylePrompt
      end
    end
    
    if customAktif and customPrompt ~= "" then
      systemRule = systemRule .. "\n\n[ATURAN KETAT]: Berikan hasil akhir secara langsung tanpa komentar, tanpa penjelasan, dan tanpa kata pengantar apapun. Hanya teks hasil olahan sesuai instruksi."
      systemRule = systemRule .. "\n[CUSTOM RULE]: " .. customPrompt
    end

    if getBool("use_emoji") then
      local eType = getPref("emoji_type", "Netral")
      local ePos = getPref("emoji_position", "Akhir Kalimat Saja")
      local emojiInstr = ""
      if eType == "Cewek" then emojiInstr = "Add 1-2 feminine emojis naturally."
      elseif eType == "Cowok" then emojiInstr = "Add 1-2 masculine emojis naturally."
      elseif eType == "Hujan" then emojiInstr = "Add 1-2 sad/rain emojis naturally."
      elseif eType == "Ceria" then emojiInstr = "Add 1-2 cheerful emojis naturally."
      else emojiInstr = "Add 1-2 context-appropriate emojis." end
      local posRule = ""
      if ePos == "Awal Kalimat Saja" then posRule = " Place ONLY at the START of the text."
      elseif ePos == "Akhir Kalimat Saja" then posRule = " Place ONLY at the END of the text."
      else posRule = " Place at BOTH the START and END of the text." end
      systemRule = systemRule .. " EMOJI: " .. emojiInstr .. posRule
    end

    local historyText = ""
    if getBool("use_memory_mode") then
      local sHist, hist = pcall(cjson.decode, getPref("chat_history_smart", "[]"))
      if sHist and type(hist) == "table" and #hist > 0 then
        historyText = "\n\n[KONTEKS PERCAKAPAN SEBELUMNYA]:\n"
        for i = math.max(1, #hist - 2), #hist do
          historyText = historyText .. "User: " .. hist[i].user .. "\nAI: " .. hist[i].ai .. "\n"
        end
      end
    end

    local userContent = historyText .. "\n" .. inputAman
    local fullPrompt = systemRule .. "\n\nINPUT TEXT TO PROCESS: " .. userContent .. "\n\nOUTPUT:"

    local function handleAIResult(out)
      if not out or out == "" then return end
      local clean = out:gsub("^%s*(.-)%s*$", "%1"):gsub('^"(.*)"$', "%1")
      clean = clean:gsub("^%*%*.-%*%*%s*", "")
      clean = clean:gsub("^Berikut.-:%s*", "")
      callback(terapkanSemuaGaya(clean))
      vibrate(60)
    end

    local provider = getPref("active_provider", "Gemini")
    if provider == "Gemini" then
      local apiKey = getPref("gemini_api_key", ""):gsub("%s+", "")
      local model = getPref("gemini_model", "gemini-1.5-flash"):gsub("^models/", "")
      local payload = { contents = { { parts = { { text = fullPrompt } } } }, generationConfig = { temperature = 0.2 } }
      Http.post("https://generativelanguage.googleapis.com/v1beta/models/"..model..":generateContent?key="..apiKey, cjson.encode(payload), {["Content-Type"]="application/json"}, function(c, content)
        if c == 200 then 
          local s, res = pcall(cjson.decode, content) 
          if s and res and res.candidates and res.candidates[1] and res.candidates[1].content and res.candidates[1].content.parts and res.candidates[1].content.parts[1] then 
            handleAIResult(res.candidates[1].content.parts[1].text) 
          end 
        else
          pesan("Gagal akses Gemini! Kode status: " .. tostring(c))
        end
      end)
    elseif provider == "Groq" then
      local apiKey = getPref("groq_api_key", ""):gsub("%s+", "")
      Http.post("https://api.groq.com/openai/v1/chat/completions", cjson.encode({model=getPref("groq_model", "llama-3.3-70b-versatile"), messages={{role="system", content=systemRule},{role="user", content=userContent}}, temperature=0.2}), {["Content-Type"]="application/json", ["Authorization"]="Bearer "..apiKey}, function(c, content)
        if c == 200 then 
          local s, res = pcall(cjson.decode, content) 
          if s and res and res.choices and res.choices[1] and res.choices[1].message then 
            handleAIResult(res.choices[1].message.content) 
          end 
        end
      end)
    elseif provider == "ChatGPT Gratis" then
      local url = "https://soffiapis.my.id/api/ai/gpt-free"
      local payload = cjson.encode({q = fullPrompt})
      Http.post(url, payload, {["Content-Type"]="application/json"}, function(c, content)
        if c == 200 then
          local s, res = pcall(cjson.decode, content)
          if s and res and res.data and res.data.reply then handleAIResult(res.data.reply) else handleAIResult(content) end
        else pesan("Gagal akses ChatGPT Gratis: " .. c) end
      end)
    end
  end

  if getBool("use_translate") then
    if getBool("use_ai_translate") then
      local targetLangName = getPref("translate_lang", "English")
      local targetLangCode = "en"
      local locales = Locale.getAvailableLocales()
      for i=0, #locales-1 do if locales[i].getDisplayName() == targetLangName then targetLangCode = locales[i].getLanguage() if targetLangCode == "zh" then targetLangCode = "zh-CN" end break end end
      local aiTranslatePrompt = "Translate the following text into "..targetLangName.." naturally, preserving the exact meaning and tone. Output ONLY the translated text."
      local fullPromptTranslate = aiTranslatePrompt .. "\n\nTEXT: " .. userInput .. "\n\nTRANSLATION:"
      local function handleAIResultTranslate(out)
        if not out or out == "" then return end
        local clean = out:gsub("^%s*(.-)%s*$", "%1"):gsub('^"(.*)"$', "%1")
        callback(terapkanSemuaGaya(clean))
        vibrate(60)
      end
      local provider = getPref("active_provider", "Gemini")
      if provider == "Gemini" then
        local apiKey = getPref("gemini_api_key", ""):gsub("%s+", "")
        local model = getPref("gemini_model", "gemini-1.5-flash"):gsub("^models/", "")
        local payload = { contents = { { parts = { { text = fullPromptTranslate } } } }, generationConfig = { temperature = 0.2 } }
        Http.post("https://generativelanguage.googleapis.com/v1beta/models/"..model..":generateContent?key="..apiKey, cjson.encode(payload), {["Content-Type"]="application/json"}, function(c, content)
          if c == 200 then 
            local s, res = pcall(cjson.decode, content) 
            if s and res and res.candidates and res.candidates[1] and res.candidates[1].content and res.candidates[1].content.parts and res.candidates[1].content.parts[1] then 
              handleAIResultTranslate(res.candidates[1].content.parts[1].text) 
            end 
          end
        end)
      elseif provider == "Groq" then
        local apiKey = getPref("groq_api_key", ""):gsub("%s+", "")
        Http.post("https://api.groq.com/openai/v1/chat/completions", cjson.encode({model=getPref("groq_model", "llama-3.3-70b-versatile"), messages={{role="user", content=fullPromptTranslate}}, temperature=0.2}), {["Content-Type"]="application/json", ["Authorization"]="Bearer "..apiKey}, function(c, content)
          if c == 200 then 
            local s, res = pcall(cjson.decode, content) 
            if s and res and res.choices and res.choices[1] and res.choices[1].message then 
              handleAIResultTranslate(res.choices[1].message.content) 
            end 
          end
        end)
      elseif provider == "ChatGPT Gratis" then
        local url = "https://soffiapis.my.id/api/ai/gpt-free"
        local payload = cjson.encode({q = fullPromptTranslate})
        Http.post(url, payload, {["Content-Type"]="application/json"}, function(c, content)
          if c == 200 then
            local s, res = pcall(cjson.decode, content)
            if s and res and res.data and res.data.reply then handleAIResultTranslate(res.data.reply) else handleAIResultTranslate(content) end
          end
        end)
      end
    else
      local toLang = "en"
      local targetLangName = getPref("translate_lang", "English")
      local locales = Locale.getAvailableLocales()
      for i=0, #locales-1 do if locales[i].getDisplayName() == targetLangName then toLang = locales[i].getLanguage() if toLang == "zh" then toLang = "zh-CN" end break end end
      local postBody = "client=gtx&sl=auto&tl="..toLang.."&dt=t&q="..Uri.encode(userInput)
      Http.post("https://translate.googleapis.com/translate_a/single", postBody, {["User-Agent"]="Mozilla/5.0", ["Content-Type"]="application/x-www-form-urlencoded"}, function(code, content)
        if code == 200 then 
          local s, res = pcall(cjson.decode, content) 
          if s and res and res[1] then 
            local hasilTr = "" 
            for i=1, #res[1] do if res[1][i][1] then hasilTr = hasilTr .. res[1][i][1] end end 
            callback(terapkanSemuaGaya(hasilTr)) 
            vibrate(60) 
          end 
        end
      end)
    end
  else
    if getBool("use_ai_process") then eksekusiAI(userInput) else callback(terapkanSemuaGaya(userInput)) end
  end
end

function addChatMemory(userText, aiText)
  local maxEntries = 30
  local s, hist = pcall(cjson.decode, getPref("chat_history_smart", "[]"))
  if not s or type(hist) ~= "table" then hist = {} end
  table.insert(hist, {user = userText, ai = aiText, time = os.date("%H:%M")})
  if #hist > maxEntries then
    table.remove(hist, 1)
  end
  setPref("chat_history_smart", cjson.encode(hist))
end

local function showChatHistory()
  local s, hist = pcall(cjson.decode, getPref("chat_history_smart", "[]"))
  if not s or type(hist) ~= "table" then hist = {} end

  local scroll = ScrollView(service)
  local layHist = LinearLayout(service).setOrientation(1).setPadding(30,30,30,30)
  scroll.addView(layHist)

  if #hist == 0 then
    layHist.addView(TextView(service).setText("Belum ada riwayat chat.").setTextSize(16))
  else
    for i, entry in ipairs(hist) do
      local card = LinearLayout(service).setOrientation(1).setPadding(10,10,10,10)
      card.setBackgroundColor(0xFFF0F0F0)
      local tvUser = TextView(service).setText("🧑 Anda ("..entry.time.."): " .. entry.user).setTextSize(16).setTextColor(0xFF000000)
      local tvAI = TextView(service).setText("🤖 AI: " .. entry.ai).setTextSize(16).setTextColor(0xFF333333)
      card.addView(tvUser)
      card.addView(tvAI)
      layHist.addView(card)
      layHist.addView(TextView(service).setText("--------------------------------"))
    end
  end

  local btnClear = Button(service).setText("Hapus Semua Riwayat")
  btnClear.setOnClickListener(function()
    local d = LuaDialog(service)
    d.setTitle("Konfirmasi")
    d.setMessage("Hapus semua riwayat chat?")
    d.setPositiveButton("Ya", {onClick=function()
      setPref("chat_history_smart", "[]")
      pesan("Riwayat chat dihapus!")
      d.dismiss()
      showChatHistory()
    end})
    d.setNegativeButton("Batal", nil)
    d.show()
  end)
  layHist.addView(btnClear)

  local dlg = LuaDialog(service)
  dlg.setTitle("Riwayat Chat")
  dlg.setView(scroll)
  dlg.setPositiveButton("Tutup", nil)
  dlg.show()
end

local function showPengaturanGayaVokal()
  local layV = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
  layV.addView(TextView(service).setText("Pilih Vokal:"))
  local cbAIUEO = CheckBox(service).setText("Gunakan Vokal AIUEO")
  local cbA = CheckBox(service).setText("Gunakan Vokal A saja")
  local cbI = CheckBox(service).setText("Gunakan Vokal I")
  local cbCadel = CheckBox(service).setText("Gunakan Gaya Cadel")
  layV.addView(cbAIUEO) layV.addView(cbA) layV.addView(cbI) layV.addView(cbCadel)
  local vokalCharSet = getPref("vokal_char_set", "AIUEO")
  if vokalCharSet == "AIUEO" then cbAIUEO.setChecked(true)
  elseif vokalCharSet == "A" then cbA.setChecked(true)
  elseif vokalCharSet == "I" then cbI.setChecked(true)
  elseif vokalCharSet == "Cadel C" then cbCadel.setChecked(true) end
  local function updateVokalSelection(mode)
    cbAIUEO.setChecked(mode == "AIUEO") cbA.setChecked(mode == "A") cbI.setChecked(mode == "I") cbCadel.setChecked(mode == "Cadel C")
    setPref("vokal_char_set", mode)
  end
  cbAIUEO.setOnCheckedChangeListener{onCheckedChanged=function(v, c) if c then updateVokalSelection("AIUEO") end end}
  cbA.setOnCheckedChangeListener{onCheckedChanged=function(v, c) if c then updateVokalSelection("A") end end}
  cbI.setOnCheckedChangeListener{onCheckedChanged=function(v, c) if c then updateVokalSelection("I") end end}
  cbCadel.setOnCheckedChangeListener{onCheckedChanged=function(v, c) if c then updateVokalSelection("Cadel C") end end}
  if not cbAIUEO.isChecked() and not cbA.isChecked() and not cbI.isChecked() and not cbCadel.isChecked() then updateVokalSelection("AIUEO") end
  layV.addView(TextView(service).setText("\nJumlah Pengulangan:"))
  local etV = EditText(service).setText(getPref("vokal_count", "2")).setInputType(2)
  layV.addView(etV)
  local dlg = LuaDialog(service)
  dlg.setTitle("Pengaturan Gaya Vokal")
  dlg.setView(layV)
  dlg.setPositiveButton("Tutup", {onClick=function()
    local count = tonumber(etV.getText().toString())
    if count and count >= 1 then setPref("vokal_count", tostring(count)) pesan("Disimpan sementara!") else pesan("Jumlah pengulangan harus angka dan minimal 1.") end
  end})
  dlg.show()
end

-- ==================== MENU UTAMA ====================
function showMain()
  initTempPrefs()  -- reset tempPrefsData setiap kali menu utama dibuka
  local root = ScrollView(service)
  local lay = LinearLayout(service).setOrientation(1).setPadding(30,20,30,30)
  root.addView(lay)
  local function addBtn(t, cb) local b = Button(service).setText(t) b.setOnClickListener(cb) lay.addView(b) return b end
  local mainDialog

  addBtn("Fitur AI", function()
    local layAI = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
    local chkGaya = CheckBox(service).setText("Aktifkan Gaya Bicara AI").setChecked(getBool("use_ai_style"))
    chkGaya.setOnCheckedChangeListener{onCheckedChanged=function(v, c) setBool("use_ai_style", c) end}
    layAI.addView(chkGaya)
    
    local btnGaya = Button(service).setText("Pilih Gaya/Kategori: " .. getPref("ai_feature_title", "Belum dipilih"))
    btnGaya.setOnClickListener(function()
      local cats = getUniqueCategories()
      local layCat = LinearLayout(service).setOrientation(1).setPadding(20,20,20,20)
      local listCat = ListView(service)
      local adapterCat = ArrayAdapter(service, android.R.layout.simple_list_item_1, cats)
      listCat.setAdapter(adapterCat)
      layCat.addView(listCat)
      local dlgCat = LuaDialog(service)
      dlgCat.setTitle("Pilih Kategori Gaya")
      dlgCat.setView(layCat)
      listCat.setOnItemClickListener{onItemClick=function(parent, view, pos, id)
        local selectedCat = cats[pos+1]
        local features = {}
        for idx, feat in ipairs(AI_FEATURES) do
          if feat.category == selectedCat then
            table.insert(features, {title=feat.title, index=idx})
          end
        end
        local featureTitles = {}
        for _, f in ipairs(features) do table.insert(featureTitles, f.title) end
        dlgCat.dismiss()
        local layFeat = LinearLayout(service).setOrientation(1).setPadding(20,20,20,20)
        local listFeat = ListView(service)
        local adapterFeat = ArrayAdapter(service, android.R.layout.simple_list_item_1, featureTitles)
        listFeat.setAdapter(adapterFeat)
        layFeat.addView(listFeat)
        local dlgFeat = LuaDialog(service)
        dlgFeat.setTitle(selectedCat)
        dlgFeat.setView(layFeat)
        listFeat.setOnItemClickListener{onItemClick=function(parent2, view2, pos2, id2)
          local selectedFeature = features[pos2+1]
          setPref("ai_feature_index", tostring(selectedFeature.index))
          setPref("ai_feature_title", selectedFeature.title)
          btnGaya.setText("Pilih Gaya/Kategori: " .. selectedFeature.title)
          pesan("Gaya dipilih: " .. selectedFeature.title)
          dlgFeat.dismiss()
        end}
        dlgFeat.setNegativeButton("Kembali", {onClick=function(d2) d2.dismiss() end})
        dlgFeat.show()
      end}
      dlgCat.setNegativeButton("Tutup", {onClick=function(d) d.dismiss() end})
      dlgCat.show()
    end)
    layAI.addView(btnGaya)

    local providerList = {"Gemini", "Groq", "ChatGPT Gratis"}
    local spinProv = Spinner(service).setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_dropdown_item, providerList))
    local currentProv = getPref("active_provider", "Gemini")
    for i, v in ipairs(providerList) do if v == currentProv then spinProv.setSelection(i-1) break end end
    layAI.addView(TextView(service).setText("\nProvider:"))
    layAI.addView(spinProv)

    local layApi = LinearLayout(service).setOrientation(1)
    local etApiKey = EditText(service).setHint("Masukkan API Key")
    local btnAmbilModel = Button(service).setText("Ambil Daftar Model")
    local btnGetKey = Button(service).setText("Dapatkan Kunci API")
    local spinModel = Spinner(service)
    local function updateModelList()
      local p = providerList[spinProv.getSelectedItemPosition()+1]
      local s, models = pcall(cjson.decode, getPref(p:lower().."_models_list", "[]"))
      if not s or type(models) ~= "table" then models = {} end
      spinModel.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_dropdown_item, models))
      local curModel = getPref(p:lower().."_model", "")
      for i, m in ipairs(models) do if m == curModel then spinModel.setSelection(i-1) break end end
    end
    local function loadApiKey()
      local p = providerList[spinProv.getSelectedItemPosition()+1]
      if p == "ChatGPT Gratis" then etApiKey.setText("") else etApiKey.setText(getPref(p:lower().."_api_key", "")) end
    end
    local function setApiVisibility()
      local p = providerList[spinProv.getSelectedItemPosition()+1]
      if p == "ChatGPT Gratis" then
        layApi.setVisibility(View.GONE)
      else
        layApi.setVisibility(View.VISIBLE)
        loadApiKey()
        updateModelList()
      end
    end
    layApi.addView(etApiKey)
    layApi.addView(btnAmbilModel)
    layApi.addView(btnGetKey)
    layApi.addView(TextView(service).setText("Model:"))
    layApi.addView(spinModel)
    layAI.addView(layApi)
    setApiVisibility()

    spinProv.setOnItemSelectedListener(luajava.createProxy("android.widget.AdapterView$OnItemSelectedListener", {
      onItemSelected = function(parent, view, pos, id) setApiVisibility() end,
      onNothingSelected = function(parent) end
    }))

    btnAmbilModel.setOnClickListener(function()
      local p = providerList[spinProv.getSelectedItemPosition()+1]
      local apiKey = etApiKey.getText().toString():gsub("%s+", "")
      if apiKey == "" then pesan("Isi API Key dulu!") return end
      pesan("Mengambil model "..p.."...")
      if p == "Gemini" then
        Http.get("https://generativelanguage.googleapis.com/v1beta/models?key="..apiKey, function(c, content)
          if c == 200 then
            local s, res = pcall(cjson.decode, content)
            if s and res and res.models then
              local nm = {}
              for _, m in pairs(res.models) do 
                if m.name then 
                  local mn = m.name:lower() 
                  if mn:find("gemini") or mn:find("gemma") then 
                    local namaBersih = m.name:gsub("^models/", "")
                    table.insert(nm, namaBersih) 
                  end 
                end 
              end
              setPref("gemini_models_list", cjson.encode(nm)) 
              updateModelList() 
              pesan("Model Gemini diperbarui (" .. #nm .. " model)")
            else
              pesan("Respon dari Gemini tidak valid!")
            end
          else 
            pesan("Gagal mengambil model! Kode HTTP: "..tostring(c)) 
          end
        end)
      elseif p == "Groq" then
        Http.get("https://api.groq.com/openai/v1/models", {["Authorization"]="Bearer "..apiKey}, function(c, content)
          if c == 200 then
            local s, res = pcall(cjson.decode, content)
            if s and res and res.data then
              local nm = {}
              for _, m in ipairs(res.data) do table.insert(nm, m.id) end
              setPref("groq_models_list", cjson.encode(nm)) updateModelList() pesan("Model Groq diperbarui")
            end
          else pesan("Gagal: "..c) end
        end)
      end
    end)

    btnGetKey.setOnClickListener(function()
      local p = providerList[spinProv.getSelectedItemPosition()+1]
      local url = ""
      if p == "Gemini" then url = "https://aistudio.google.com/app/apikey"
      elseif p == "Groq" then url = "https://console.groq.com/keys"
      else return end
      pesan("Membuka Google Chrome")
      local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
      intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      service.startActivity(intent)
    end)

    local function simpanFiturAI()
      local p = providerList[spinProv.getSelectedItemPosition()+1]
      setPref("active_provider", p)
      if p ~= "ChatGPT Gratis" then
        setPref(p:lower().."_api_key", etApiKey.getText().toString():gsub("%s+", ""))
        local selectedModel = tostring(spinModel.getSelectedItem())
        if selectedModel and selectedModel ~= "" and selectedModel ~= "nil" then setPref(p:lower().."_model", selectedModel) end
      end
      pesan("Pengaturan AI disiapkan sementara!")
    end

    local dlgAI = LuaDialog(service)
    dlgAI.setTitle("Fitur AI")
    dlgAI.setView(layAI)
    dlgAI.setPositiveButton("Simpan", {onClick=function() simpanFiturAI() end})
    dlgAI.setNegativeButton("Batal", nil)
    dlgAI.show()
  end)

  -- Terjemahan
  addBtn("Terjemahan", function()
    local scroll = ScrollView(service)
    local layUtama = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
    scroll.addView(layUtama)
    local cacheBahasa = getPref("daftar_bahasa_sinkron", "[]")
    local s, DAFTAR_BAHASA = pcall(cjson.decode, cacheBahasa)
    if not s or type(DAFTAR_BAHASA) ~= "table" or #DAFTAR_BAHASA == 0 then 
      DAFTAR_BAHASA = {"Indonesia", "English", "Japanese", "Arabic", "Chinese"} 
    end
    layUtama.addView(TextView(service).setText("Pengaturan Terjemahan:").setTypeface(Typeface.DEFAULT_BOLD))
    local swTrans = Switch(service).setText("Aktifkan Terjemahan").setChecked(getBool("use_translate"))
    swTrans.setOnCheckedChangeListener{onCheckedChanged=function(v, c) setBool("use_translate", c) end}
    layUtama.addView(swTrans)
    local swAITrans = Switch(service).setText("Terjemahkan dengan AI").setChecked(getBool("use_ai_translate"))
    swAITrans.setOnCheckedChangeListener{onCheckedChanged=function(v, c) setBool("use_ai_translate", c) end}
    layUtama.addView(swAITrans)
    local btnAsal, btnTujuan
    local function showLanguagePicker(title, prefKey, targetButton, prefix)
      local layCari = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
      local etSearch = EditText(service).setHint("Cari bahasa...")
      local listV = ListView(service)
      local listWithDetect = {"Deteksi Otomatis"}
      for _, v in ipairs(DAFTAR_BAHASA) do table.insert(listWithDetect, v) end
      local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, listWithDetect)
      listV.setAdapter(adapter)
      etSearch.addTextChangedListener{onTextChanged=function(s) adapter.getFilter().filter(tostring(s)) end}
      layCari.addView(etSearch) layCari.addView(listV)
      local dl = LuaDialog(service)
      dl.setTitle(title)
      dl.setView(layCari)
      dl.setNegativeButton("Batal", nil)
      dl.show()
      listV.setOnItemClickListener{onItemClick=function(parent, view, pos, id)
        local selected = tostring(adapter.getItem(pos))
        setPref(prefKey, selected)
        targetButton.setText(prefix .. selected)
        pesan("Dipilih: " .. selected)
        dl.dismiss()
      end}
    end
    layUtama.addView(TextView(service).setText("\nBahasa Asal:").setPadding(0,20,0,0))
    btnAsal = Button(service).setText("Dari: " .. getPref("lang_asal_pilihan", "Deteksi Otomatis"))
    btnAsal.setOnClickListener(function() showLanguagePicker("Pilih Bahasa Asal", "lang_asal_pilihan", btnAsal, "Dari: ") end)
    layUtama.addView(btnAsal)
    layUtama.addView(TextView(service).setText("\nBahasa Tujuan:").setPadding(0,20,0,0))
    btnTujuan = Button(service).setText("Ke: " .. getPref("translate_lang", "English"))
    btnTujuan.setOnClickListener(function() showLanguagePicker("Pilih Bahasa Tujuan", "translate_lang", btnTujuan, "Ke: ") end)
    layUtama.addView(btnTujuan)
    local btnUpdateLang = Button(service).setText("Update Bahasa dari Sistem")
    btnUpdateLang.setOnClickListener(function()
      vibrate(60)
      local locales = Locale.getAvailableLocales()
      local temp, seen = {}, {}
      for i=0, #locales-1 do local name = locales[i].getDisplayName() if name ~= "" and not seen[name] then table.insert(temp, name) seen[name] = true end end
      table.sort(temp)
      setPref("daftar_bahasa_sinkron", cjson.encode(temp))
      pesan("Berhasil sinkron " .. #temp .. " bahasa!")
    end)
    layUtama.addView(btnUpdateLang)
    local dlgTr = LuaDialog(service)
    dlgTr.setTitle("Terjemahan")
    dlgTr.setView(scroll)
    dlgTr.setPositiveButton("Tutup", nil)
    dlgTr.show()
  end)

  -- Pengaturan Emoji
  addBtn("Pengaturan Emoji", function()
    local layE = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
    local cbE = CheckBox(service).setText("Aktifkan Emoji").setChecked(getBool("use_emoji"))
    layE.addView(cbE)
    local jenisEmoji = {"Netral", "Cewek", "Cowok", "Hujan", "Ceria"}
    local posisiEmoji = {"Awal Kalimat Saja", "Akhir Kalimat Saja", "Awal & Akhir Kalimat"}
    local spJenis = Spinner(service).setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_dropdown_item, jenisEmoji))
    local curJenis = getPref("emoji_type", "Netral")
    for i, v in ipairs(jenisEmoji) do if v == curJenis then spJenis.setSelection(i-1) break end end
    layE.addView(TextView(service).setText("Jenis Emoji:"))
    layE.addView(spJenis)
    local spPosisi = Spinner(service).setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_dropdown_item, posisiEmoji))
    local curPosisi = getPref("emoji_position", "Akhir Kalimat Saja")
    for i, v in ipairs(posisiEmoji) do if v == curPosisi then spPosisi.setSelection(i-1) break end end
    layE.addView(TextView(service).setText("Posisi Emoji:"))
    layE.addView(spPosisi)
    local dlgEm = LuaDialog(service)
    dlgEm.setTitle("Atur Emoji")
    dlgEm.setView(layE)
    dlgEm.setPositiveButton("Simpan", {onClick=function()
      setBool("use_emoji", cbE.isChecked())
      setPref("emoji_type", jenisEmoji[spJenis.getSelectedItemPosition()+1])
      setPref("emoji_position", posisiEmoji[spPosisi.getSelectedItemPosition()+1])
      pesan("Setelan Emoji disiapkan sementara!")
    end})
    dlgEm.setNegativeButton("Batal", nil)
    dlgEm.show()
  end)

  -- Instruksi Custom
  addBtn("Instruksi Custom", function()
    local s, data = pcall(cjson.decode, getPref("custom_prompts", "[]"))
    if not s or type(data) ~= "table" then data = {} end
    local activeIdx = tonumber(getPref("active_prompt_idx", "-1"))
    local isEnabled = getBool("use_custom_instr")

    local layout = LinearLayout(service).setOrientation(1).setPadding(20,20,20,20)
    local cbAktif = CheckBox(service).setText("Aktifkan Instruksi Custom").setChecked(isEnabled)
    cbAktif.setOnCheckedChangeListener{onCheckedChanged=function(v, c) setBool("use_custom_instr", c) end}
    layout.addView(cbAktif)

    local function updateAdapterItems(adapterObj)
      local newItems = {}
      for i, v in ipairs(data) do
        local prefix = (i-1 == activeIdx) and "✓ " or "   "
        table.insert(newItems, prefix .. v.name)
      end
      adapterObj.clear()
      for _, item in ipairs(newItems) do adapterObj.add(item) end
      adapterObj.notifyDataSetChanged()
    end

    local items = {}
    for i, v in ipairs(data) do
      local prefix = (i-1 == activeIdx) and "✓ " or "   "
      table.insert(items, prefix .. v.name)
    end
    local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, items)
    local listInstr = ListView(service)
    listInstr.setAdapter(adapter)
    layout.addView(listInstr)

    local btnTambah = Button(service).setText("Tambah Baru")
    btnTambah.setOnClickListener(function()
      local layAdd = LinearLayout(service).setOrientation(1).setPadding(40,20,40,20)
      local en = EditText(service).setHint("Nama Instruksi") local ep = EditText(service).setHint("Isi Instruksi...")
      layAdd.addView(en) layAdd.addView(ep)
      local dlgAdd = LuaDialog(service)
      dlgAdd.setTitle("Tambah Instruksi")
      dlgAdd.setView(layAdd)
      dlgAdd.setPositiveButton("Simpan", {onClick=function()
        local name, prompt = en.getText().toString(), ep.getText().toString()
        if name ~= "" and prompt ~= "" then
          table.insert(data, {name=name, text=prompt})
          setPref("custom_prompts", cjson.encode(data))
          activeIdx = #data - 1
          setPref("active_prompt_idx", tostring(activeIdx))
          setPref("active_custom_prompt", prompt)
          pesan("Instruksi baru ditambahkan")
          updateAdapterItems(adapter)
          setBool("use_custom_instr", true)
          cbAktif.setChecked(true)
        end
      end})
      dlgAdd.setNegativeButton("Batal", nil)
      dlgAdd.show()
    end)
    layout.addView(btnTambah)

    listInstr.setOnItemClickListener{onItemClick=function(parent, view, pos, id)
      if activeIdx == pos then
        setPref("active_prompt_idx", "-1") setPref("active_custom_prompt", "")
        activeIdx = -1
        cbAktif.setChecked(false)
        setBool("use_custom_instr", false)
        pesan("Instruksi tidak terpilih")
      else
        setPref("active_prompt_idx", tostring(pos)) setPref("active_custom_prompt", data[pos+1].text)
        activeIdx = pos
        setBool("use_custom_instr", true)
        cbAktif.setChecked(true)
        pesan("Terpilih: " .. data[pos+1].name)
      end
      updateAdapterItems(adapter)
    end}

    listInstr.setOnItemLongClickListener{onItemLongClick=function(parent, view, pos, id)
      local idx = pos + 1
      local layOpt = LinearLayout(service).setOrientation(1).setPadding(40,20,40,20)
      local tvInfo = TextView(service).setText("Instruksi: " .. data[idx].name).setTextSize(16)
      layOpt.addView(tvInfo)
      local btnEdit = Button(service).setText("Edit")
      local btnHapus = Button(service).setText("Hapus")
      layOpt.addView(btnEdit)
      layOpt.addView(btnHapus)

      local dlgOpt = LuaDialog(service)
      dlgOpt.setTitle("Opsi Instruksi")
      dlgOpt.setView(layOpt)
      dlgOpt.setNegativeButton("Batal", {onClick=function(d) d.dismiss() end})
      dlgOpt.show()

      btnEdit.setOnClickListener(function()
        dlgOpt.dismiss()
        local layEdit = LinearLayout(service).setOrientation(1).setPadding(40,20,40,20)
        local en = EditText(service).setText(data[idx].name) local ep = EditText(service).setText(data[idx].text)
        layEdit.addView(en) layEdit.addView(ep)
        local dlgEdit = LuaDialog(service)
        dlgEdit.setTitle("Edit Instruksi")
        dlgEdit.setView(layEdit)
        dlgEdit.setPositiveButton("Simpan", {onClick=function()
          data[idx] = {name=en.getText().toString(), text=ep.getText().toString()} setPref("custom_prompts", cjson.encode(data))
          if activeIdx == idx-1 then setPref("active_custom_prompt", data[idx].text) end
          updateAdapterItems(adapter)
          commitPrefs()
          dlgEdit.dismiss()
        end})
        dlgEdit.setNegativeButton("Batal", {onClick=function(d) d.dismiss() end})
        dlgEdit.show()
      end)

      btnHapus.setOnClickListener(function()
        dlgOpt.dismiss()
        table.remove(data, idx) setPref("custom_prompts", cjson.encode(data))
        if activeIdx == idx-1 then setPref("active_prompt_idx", "-1") setPref("active_custom_prompt", "") activeIdx = -1 end
        updateAdapterItems(adapter)
        commitPrefs()
        pesan("Instruksi dihapus")
      end)
      return true
    end}

    local dlgIns = LuaDialog(service)
    dlgIns.setTitle("Instruksi Custom")
    dlgIns.setView(layout)
    dlgIns.setPositiveButton("Tutup", nil)
    dlgIns.show()
  end)

  -- Pengaturan Lanjutan
  addBtn("Pengaturan Lanjutan", function()
    local scroll = ScrollView(service)
    local layFitur = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
    scroll.addView(layFitur)
    local function addSwDialog(txt, key)
      local sw = Switch(service).setText(txt).setChecked(getBool(key))
      sw.setOnCheckedChangeListener{onCheckedChanged=function(v, c) setBool(key, c) end}
      layFitur.addView(sw)
    end
    layFitur.addView(TextView(service).setText("Pemrosesan Teks:").setTypeface(Typeface.DEFAULT_BOLD))
    local swModeAI = Switch(service).setText(getBool("use_ai_process") and "Mode AI (Online)" or "Mode Offline")
    swModeAI.setChecked(getBool("use_ai_process"))
    swModeAI.setOnCheckedChangeListener{onCheckedChanged=function(v, c)
      setBool("use_ai_process", c)
      swModeAI.setText(c and "Mode AI (Online)" or "Mode Offline")
      pesan(c and "Mode AI diaktifkan" or "Mode Offline diaktifkan")
    end}
    layFitur.addView(swModeAI)
    addSwDialog("Mode Revisi Teks Terdahulu", "use_revision_mode")
    addSwDialog("Dikte Berkelanjutan", "use_continuous_mode")
    
    local layTTS = LinearLayout(service).setOrientation(0).setGravity(Gravity.CENTER_VERTICAL)
    local swTTS = Switch(service).setText("Baca Hasil Suara (TTS)").setChecked(getBool("use_auto_tts"))
    swTTS.setOnCheckedChangeListener{onCheckedChanged=function(v, c) setBool("use_auto_tts", c) end}
    local btnSetTTS = Button(service).setText("Atur")
    btnSetTTS.setOnClickListener(function() showPengaturanTTS() end)
    layTTS.addView(swTTS, LinearLayout.LayoutParams(0, -2, 1.0))
    layTTS.addView(btnSetTTS)
    layFitur.addView(layTTS)

    local layG = LinearLayout(service).setOrientation(1)
    local swGetar = Switch(service).setText("Fitur Getaran").setChecked(getBool("use_vibration"))
    local laySlider = LinearLayout(service).setOrientation(1).setPadding(20,10,20,10)
    local txtValue = TextView(service)
    local skGetar = SeekBar(service).setMax(500)
    local curDur = tonumber(getPref("vibration_duration", "50"))
    skGetar.setProgress(curDur) txtValue.setText("Durasi Getar: " .. curDur .. " ms")
    skGetar.setOnSeekBarChangeListener{onProgressChanged=function(bar, prog)
      if prog < 10 then prog = 10 end
      txtValue.setText("Durasi Getar: " .. prog .. " ms") setPref("vibration_duration", tostring(prog))
      local v = service.getSystemService(Context.VIBRATOR_SERVICE) if v then v.vibrate(prog) end
    end}
    laySlider.addView(txtValue) laySlider.addView(skGetar)
    laySlider.setVisibility(getBool("use_vibration") and View.VISIBLE or View.GONE)
    swGetar.setOnCheckedChangeListener{onCheckedChanged=function(v, c)
      setBool("use_vibration", c) laySlider.setVisibility(c and View.VISIBLE or View.GONE) if c then vibrate() end
    end}
    layG.addView(swGetar) layG.addView(laySlider) layFitur.addView(layG)
    addSwDialog("Mode Tanpa Spasi", "use_no_space")
    addSwDialog("Mode Singkatan Nomor", "use_singkatan")
    addSwDialog("Tanda Baca Brutal", "use_brutal_punc")
    addSwDialog("Tampilkan Konfirmasi Saat Klik", "use_confirmation")
    addSwDialog("Aktifkan Mode Hantu", "use_ghost_mode")

    layFitur.addView(TextView(service).setText("\nMemori Cerdas:").setPadding(10,15,10,5))
    addSwDialog("Aktifkan Mode Ingatan", "use_memory_mode")
    local layMemori = LinearLayout(service).setOrientation(0)
    local btnRiwayat = Button(service).setText("Riwayat Chat")
    btnRiwayat.setOnClickListener(function()
      showChatHistory()
    end)
    layMemori.addView(btnRiwayat)
    layFitur.addView(layMemori)

    layFitur.addView(TextView(service).setText("\nPengaturan Gaya Vokal:").setPadding(10,15,10,5))
    local layVokal = LinearLayout(service).setOrientation(0).setGravity(Gravity.CENTER_VERTICAL)
    local swVokal = Switch(service).setText("Aktifkan Gaya Vokal").setChecked(getBool("use_gaya_vokal"))
    swVokal.setOnCheckedChangeListener{onCheckedChanged=function(v, c) setBool("use_gaya_vokal", c) end}
    local btnSetVokal = Button(service).setText("Atur") btnSetVokal.setOnClickListener(function() showPengaturanGayaVokal() end)
    layVokal.addView(swVokal, LinearLayout.LayoutParams(0, -2, 1.0)) layVokal.addView(btnSetVokal) layFitur.addView(layVokal)
    local dlgAdv = LuaDialog(service)
    dlgAdv.setTitle("Pengaturan Lanjutan")
    dlgAdv.setView(scroll)
    dlgAdv.setPositiveButton("Selesai", nil)
    dlgAdv.show()
  end)

  -- Kamus Pribadi
  addBtn("Kamus Pribadi", function()
    local layK = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
    local cbK = CheckBox(service).setText("Aktifkan Kamus").setChecked(getBool("use_kamus"))
    layK.addView(cbK)

    local btnKAdd = Button(service).setText("+ Tambah Kata Baru")
    local listK = ListView(service)

    local function refK()
      local s, d = pcall(cjson.decode, getPref("kamus_json", "{}"))
      if not s or type(d) ~= "table" then d = {} end
      local keys, disp = {}, {}
      for k, v in pairs(d) do
        table.insert(keys, k)
        table.insert(disp, k .. " -> " .. v)
      end
      listK.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, disp))
      return keys, d
    end

    listK.setOnItemClickListener{onItemClick=function(parent, view, pos, id)
      local keys, data = refK()
      local kataAsli = keys[pos+1]
      local kataGanti = data[kataAsli]

      local layOpt = LinearLayout(service).setOrientation(1).setPadding(40,20,40,20)
      local tvInfo = TextView(service).setText("Kata: " .. kataAsli).setTextSize(16)
      layOpt.addView(tvInfo)

      local btnEdit = Button(service).setText("Edit")
      local btnHapus = Button(service).setText("Hapus")
      layOpt.addView(btnEdit)
      layOpt.addView(btnHapus)

      local dlgOpt = LuaDialog(service)
      dlgOpt.setTitle("Opsi Kamus")
      dlgOpt.setView(layOpt)
      dlgOpt.setNegativeButton("Batal", {onClick=function(d) d.dismiss() end})
      dlgOpt.show()

      btnEdit.setOnClickListener(function()
        dlgOpt.dismiss()
        local layEdit = LinearLayout(service).setOrientation(1).setPadding(40,20,40,20)
        local e1 = EditText(service).setText(kataAsli)
        local e2 = EditText(service).setText(kataGanti)
        layEdit.addView(e1)
        layEdit.addView(e2)

        local dlgEdit = LuaDialog(service)
        dlgEdit.setTitle("Edit Kamus")
        dlgEdit.setView(layEdit)
        dlgEdit.setPositiveButton("Simpan", {onClick=function()
          data[kataAsli] = nil
          local newK = e1.getText().toString():match("^%s*(.-)%s*$")
          local newV = e2.getText().toString()
          data[newK] = newV
          setPref("kamus_json", cjson.encode(data))
          refK()
          commitPrefs()
          pesan("Kamus diperbarui")
          dlgEdit.dismiss()
        end})
        dlgEdit.setNegativeButton("Batal", {onClick=function(d) d.dismiss() end})
        dlgEdit.show()
      end)

      btnHapus.setOnClickListener(function()
        dlgOpt.dismiss()
        data[kataAsli] = nil
        setPref("kamus_json", cjson.encode(data))
        refK()
        commitPrefs()
        pesan("Terhapus: " .. kataAsli)
      end)
    end}

    btnKAdd.setOnClickListener(function()
      local layAdd = LinearLayout(service).setOrientation(1).setPadding(40,20,40,20)
      local e1 = EditText(service).setHint("Kata Asli")
      local e2 = EditText(service).setHint("Kata Pengganti")
      layAdd.addView(e1)
      layAdd.addView(e2)

      local dlgAdd = LuaDialog(service)
      dlgAdd.setTitle("Tambah Kamus")
      dlgAdd.setView(layAdd)
      dlgAdd.setPositiveButton("Simpan", {onClick=function()
        local s, d = pcall(cjson.decode, getPref("kamus_json", "{}"))
        if not s or type(d) ~= "table" then d = {} end
        local newK = e1.getText().toString():match("^%s*(.-)%s*$")
        local newV = e2.getText().toString()
        d[newK] = newV
        setPref("kamus_json", cjson.encode(d))
        refK()
        commitPrefs()
        pesan("Kata baru ditambahkan")
        dlgAdd.dismiss()
      end})
      dlgAdd.setNegativeButton("Batal", {onClick=function(d) d.dismiss() end})
      dlgAdd.show()
    end)

    layK.addView(btnKAdd)
    layK.addView(listK)
    refK()

    local dlgKam = LuaDialog(service)
    dlgKam.setTitle("Kamus Pribadi")
    dlgKam.setView(layK)
    dlgKam.setPositiveButton("Selesai", {onClick=function()
      setBool("use_kamus", cbK.isChecked())
      commitPrefs()
      dlgKam.dismiss()
    end})
    dlgKam.show()
  end)

  -- Cadangkan & Pulihkan
  local function getBackupPath()
    return (getPref("backup_path", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).getAbsolutePath())) .. "/VoiceInput_Backup.csv"
  end
  addBtn("Cadangkan & Pulihkan", function()
    local layB = LinearLayout(service).setOrientation(1).setPadding(40,40,40,40)
    local function showFolderPicker(cb)
      local curPath = Environment.getExternalStorageDirectory().getAbsolutePath()
      local function listFolder(path)
        local f = File(path) local list = f.listFiles()
        local folders = {".. (Kembali)"} local fullPaths = {f.getParentFile() and f.getParentFile().getAbsolutePath() or path}
        if list then for i=0, #list-1 do local file = list[i] if file and file.isDirectory() then table.insert(folders, "📁 "..file.getName()) table.insert(fullPaths, file.getAbsolutePath()) end end end
        local layF = LinearLayout(service).setOrientation(1).setPadding(20,20,20,20)
        local listF = ListView(service)
        local adapterF = ArrayAdapter(service, android.R.layout.simple_list_item_1, folders)
        listF.setAdapter(adapterF)
        layF.addView(listF)
        local dlgF = LuaDialog(service)
        dlgF.setTitle("Pilih Folder: "..path)
        dlgF.setView(layF)
        listF.setOnItemClickListener{onItemClick=function(parent, view, pos, id)
          if pos == 0 then
            listFolder(fullPaths[1])
          else
            listFolder(fullPaths[pos+1])
          end
          dlgF.dismiss()
        end}
        dlgF.setPositiveButton("Pilih Folder Ini", {onClick=function() cb(path) end})
        dlgF.setNegativeButton("Batal", nil)
        dlgF.show()
      end
      listFolder(curPath)
    end
    local btnInt = Button(service).setText("📷 Lokasi: "..getPref("backup_path", "Folder Download"))
    btnInt.setOnClickListener(function() showFolderPicker(function(path) setPref("backup_path", path) btnInt.setText("Lokasi: "..path) pesan("Lokasi internal disimpan") end) end)
    layB.addView(btnInt)
    layB.addView(TextView(service).setText("\n--- Aksi Data ---").setGravity(Gravity.CENTER))
    local btnBack = Button(service).setText("Cadangkan (CSV)")
    btnBack.setOnClickListener(function()
      local path = getBackupPath() local bf = File(path) if bf.exists() then bf.delete() end
      local all = prefs.getAll() local it = all.entrySet().iterator() local data = {}
      while it.hasNext() do local e = it.next() table.insert(data, tostring(e.getKey())..","..tostring(e.getValue())) end
      local content = table.concat(data, "\n")
      local ok = pcall(function() local f = io.open(path, "w") f:write(content) f:close() end)
      if ok then pesan("Berhasil dicadangkan ke: "..path) else pesan("Gagal mencadangkan!") end
    end)
    layB.addView(btnBack)
    local btnRest = Button(service).setText("Pulihkan (CSV)")
    btnRest.setOnClickListener(function()
      local path = getBackupPath() if not File(path).exists() then return pesan("File tidak ditemukan!") end
      local ok = pcall(function()
        for line in io.lines(path) do local k,v = line:match("([^,]+),(.+)") if k then if v == "true" then setBool(k, true) elseif v == "false" then setBool(k, false) else setPref(k, v) end end end
      end)
      if ok then
        pesan("Berhasil memulihkan pengaturan. Silahkan kembali ke dialog utama. Lalu klik simpan. Untuk menyimpan pengaturan secara permanen. Jika tidak disimpan. Maka tamatlah.")
      else
        pesan("Gagal memulihkan.")
      end
    end)
    layB.addView(btnRest)
    local btnReset = Button(service).setText("Reset ke Setelan Pabrik").setTextColor(0xFFFF0000)
    btnReset.setOnClickListener(function()
      local dlgReset = LuaDialog(service)
      dlgReset.setTitle("Konfirmasi Reset")
      dlgReset.setMessage("Hapus semua pengaturan?")
      dlgReset.setPositiveButton("Ya", {onClick=function()
        prefs.edit().clear().apply() pesan("Setelan pabrik berhasil!") if mainDialog then mainDialog.dismiss() end
      end})
      dlgReset.setNegativeButton("Batal", nil)
      dlgReset.show()
    end)
    layB.addView(btnReset)
    local dlgB = LuaDialog(service)
    dlgB.setTitle("Cadangkan & Pulihkan")
    dlgB.setView(layB)
    dlgB.setPositiveButton("Kembali ke dialog utama", nil)
    dlgB.show()
  end)

  -- Akhir Kalimat & Custom
  local layAkhir = LinearLayout(service).setOrientation(0).setGravity(Gravity.CENTER_VERTICAL).setPadding(10,10,10,10)
  layAkhir.addView(TextView(service).setText("Akhir Kalimat: ").setPadding(20,0,0,0))
  local opsiAkhir = {"Tidak Ada", "Spasi", "Garis Baru", "Custom"}
  local spinAkhir = Spinner(service).setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_dropdown_item, opsiAkhir))
  local curAkhir = getPref("akhir_kalimat_mode", "Tidak Ada")
  for i,v in ipairs(opsiAkhir) do if v == curAkhir then spinAkhir.setSelection(i-1) break end end
  layAkhir.addView(spinAkhir)
  lay.addView(layAkhir)

  local etCustomAkhir = EditText(service)
  etCustomAkhir.setHint("Teks yang ditambahkan di akhir kalimat")
  etCustomAkhir.setVisibility(View.GONE)
  etCustomAkhir.setText(getPref("akhir_kalimat_custom", ""))
  lay.addView(etCustomAkhir)

  spinAkhir.setOnItemSelectedListener{onItemSelected=function(parent, view, pos, id)
    local pilihan = opsiAkhir[pos+1]
    setPref("akhir_kalimat_mode", pilihan)
    if pilihan == "Custom" then
      etCustomAkhir.setVisibility(View.VISIBLE)
    else
      etCustomAkhir.setVisibility(View.GONE)
    end
  end}

  -- Panduan Penggunaan
  local btnPanduan = Button(service)
  btnPanduan.setText("Panduan Penggunaan")
  btnPanduan.setOnClickListener(function()
    local pScroll = ScrollView(service)
    local pLay = LinearLayout(service).setOrientation(1).setPadding(40, 40, 40, 40)
    pScroll.addView(pLay)
    pLay.addView(TextView(service).setText("Selamat datang di Voice Input Alkausar. Terima kasih telah menggunakan karya dari saya."))
    pLay.addView(TextView(service).setText([[
PANDUAN PENGGUNAAN

FITUR AI:
- Memungkinkan kamu mengubah teks hasil dikte dengan bantuan AI.
- Terdapat 3 provider: Gemini, Groq, dan ChatGPT Gratis.
- Gemini dan Groq butuh API Key; ChatGPT Gratis tidak.
- Kamu bisa memilih model AI dan mendapatkan API Key.

FITUR TERJEMAHAN:
- Aktifkan terjemahan untuk menerjemahkan hasil input suara.
- Pilih bahasa asal (termasuk Deteksi Otomatis) dan bahasa tujuan.
- Ada opsi "Terjemahkan dengan AI" untuk hasil lebih alami.

FITUR EMOJI:
- Menambahkan emoji pada teks hasil.
- Jenis: Netral, Cewek, Cowok, Hujan, Ceria.
- Posisi: Awal saja, Akhir saja, atau Awal & Akhir.

FITUR LANJUTAN:
- Mode AI (Online) atau Offline.
- Mode Revisi Teks Terdahulu.
- Dikte Berkelanjutan.
- Baca Hasil Suara (TTS) beserta pengaturan mesin TTS, pitch, dan kecepatan.
- Fitur Getaran dengan durasi yang bisa diatur.
- Mode Tanpa Spasi, Mode Singkatan Nomor, Tanda Baca Brutal, dan Konfirmasi saat Klik.
- Mode Hantu: mengubah teks menjadi sangat kasar dan marah sesuai input.
- Memori Cerdas: mengingat percakapan sebelumnya, dengan Riwayat Chat yang bisa dihapus.
- Pengaturan Gaya Vokal: AIUEO, A saja, I saja, Cadel C.
- Akhir Kalimat: Tidak Ada, Spasi, Garis Baru, atau Custom (teks tambahan di akhir).

FITUR KAMUS PRIBADI:
- Menambah, mengedit, dan menghapus kata-kata untuk mengganti otomatis saat dikte.
- Pastikan kotak "Aktifkan Kamus" dicentang agar penggantian berfungsi.

FITUR CADANGKAN & PULIHKAN:
- Menyimpan atau memulihkan semua pengaturan ke/dari file CSV.
- Lokasi penyimpanan bisa dipilih.
- Gunakan tombol "Kembali ke dialog utama" setelah memulihkan.

CARA PENGGUNAAN:
1. Buka aplikasi target dan fokus pada kotak teks.
2. Aktifkan fitur input suara (biasanya dengan klik atau konfirmasi).
3. Ucapkan kalimat, maka teks akan diproses sesuai pengaturan.
4. Jika Mode AI aktif, hasil akan dirapikan atau diubah sesuai gaya.
5. Jika Mode Hantu aktif, teks akan diubah menjadi kasar sesuai permintaan.
6. Semua pengaturan dapat disesuaikan di menu utama dan disimpan.

TEKAN TOMBOL PUTAR DI BAWAH UNTUK MENDENGARKAN PANDUAN INI SECARA AUDIO.
]]))

    local mediaPlay = nil
    local btnPlay = Button(service).setText("▶ Putar Audio")
    local btnStop = Button(service).setText("⏹ Hentikan Audio")
    
    btnPlay.setOnClickListener(function()
      pcall(function()
        if mediaPlay then 
          mediaPlay.stop() 
          mediaPlay.release() 
          mediaPlay = nil 
        end
      end)
      local audioPath = "/storage/emulated/0/解说/Plugin/imput alkausar/audiobooks 00"
      local fObj = File(audioPath)
      if fObj.exists() then
        mediaPlay = MediaPlayer()
        mediaPlay.setDataSource(audioPath)
        mediaPlay.prepare()
        mediaPlay.start()
        pesan("Memutar audio panduan...")
      else
        pesan("File audio tidak ditemukan di direktori tersebut!")
      end
    end)
    
    btnStop.setOnClickListener(function()
      pcall(function()
        if mediaPlay then
          mediaPlay.stop()
          mediaPlay.release()
          mediaPlay = nil
          pesan("Audio dihentikan.")
        end
      end)
    end)
    
    pLay.addView(btnPlay)
    pLay.addView(btnStop)
    
    local pDialog = LuaDialog(service)
    pDialog.setTitle("Panduan Penggunaan")
    pDialog.setView(pScroll)
    pDialog.setNegativeButton("Tutup", {onClick=function()
      pcall(function()
        if mediaPlay then
          mediaPlay.stop()
          mediaPlay.release()
          mediaPlay = nil
        end
      end)
    end})
    pDialog.show()
  end)
  lay.addView(btnPanduan)

  -- Tentang Pengembang
  local btnDev = Button(service)
  btnDev.setText("Tentang")
  btnDev.setOnClickListener(function()
    local devLay = LinearLayout(service).setOrientation(1).setPadding(40, 40, 40, 40)
    devLay.addView(TextView(service).setText("Developer by al-kausar"))
    devLay.addView(TextView(service).setText("Terima kasih telah menggunakan karya dari saya. Bersama kita dapat mengatasi tantangan apa pun dengan semangat yang tak tergoyahkan. Jadikan setiap langkah kecil sebagai batu loncatan menuju impian besar Anda. Ingat, keberhasilan bukanlah tujuan akhir, melainkan perjalanan yang penuh pembelajaran dan pertumbuhan. Tetaplah positif, berbagi inspirasi, dan dukung satu sama lain dalam setiap kesempatan. 🌟🚀"))
    devLay.addView(TextView(service).setText(""))
    local rowJoin = LinearLayout(service).setOrientation(0)
    devLay.addView(rowJoin)
    local btnJoin = Button(service).setText("Hubungi Kausar di WhatsApp")
    btnJoin.setOnClickListener(function()
      local i = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/6282190840170"))
      i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      service.startActivity(i)
    end)
    rowJoin.addView(btnJoin)
    local devDialog = LuaDialog(service)
    devDialog.setTitle("Pengembang")
    devDialog.setView(devLay)
    devDialog.setNegativeButton("Tutup", nil)
    devDialog.show()
  end)
  lay.addView(btnDev)

  -- Tombol Simpan & Batal
  local layTombol = LinearLayout(service).setOrientation(0).setPadding(0,10,0,0)
  local btnSimpan = Button(service).setText("Simpan Konfigurasi")
  btnSimpan.setOnClickListener(function() 
    if etCustomAkhir and etCustomAkhir.getVisibility() == View.VISIBLE then
      setPref("akhir_kalimat_custom", etCustomAkhir.getText().toString())
    end
    commitPrefs()
    pesan("Pengaturan berhasil disimpan!") 
    if mainDialog then mainDialog.dismiss() end 
  end)
  local btnBatal = Button(service).setText("Batal")
  btnBatal.setOnClickListener(function() 
    pesan("Perubahan dibatalkan.")
    if mainDialog then mainDialog.dismiss() end 
  end)
  layTombol.addView(btnSimpan, LinearLayout.LayoutParams(0, -2, 1.0))
  layTombol.addView(btnBatal, LinearLayout.LayoutParams(0, -2, 1.0))
  lay.addView(layTombol)

  mainDialog = LuaDialog(service)
  mainDialog.setTitle("Menu utama")
  mainDialog.setView(root)
  mainDialog.show()
end

-- ==================== FUNGSI EKSEKUSI ====================
local function runRevision(edit)
  if not edit then pesan("Klik dulu di kotak teks!") return end
  local currentText = ""
  pcall(function()
    if edit.getText() then currentText = tostring(edit.getText()) end
  end)
  if currentText == "" or currentText == "nil" then
    pesan("Kotak teks kosong untuk direvisi!")
    return
  end
  vibrate(60)
  pesan("Sedang merapikan teks...")
  replaceText(edit, "")
  processText(currentText, function(hasil)
    replaceText(edit, hasil)
    speakText(hasil)
  end)
end

local function runSpeech(edit)
  if not edit then pesan("Klik dulu di kotak teks!") return end
  vibrate(60)
  local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
  intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "id-ID")
  intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
  
  local rec = SpeechRecognizer.createSpeechRecognizer(service)
  local silenceCount = 0
  
  local function checkAndRestart()
    if getBool("use_continuous_mode") then
      if silenceCount >= 2 then
        pesan("Dikte terhenti otomatis (2x hening).")
        pcall(function() rec.destroy() end)
        return
      end
      Handler(Looper.getMainLooper()).postDelayed(Runnable({
        run = function()
          pcall(function() rec.startListening(intent) end)
        end
      }), 400)
    end
  end

  rec.setRecognitionListener(luajava.createProxy("android.speech.RecognitionListener", {
    onResults = function(res)
      local list = res.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
      if list and list.size() > 0 then
        silenceCount = 0
        local hasilSuara = tostring(list.get(0))
        processText(hasilSuara, function(hasil)
          if getBool("use_continuous_mode") then
            local curText = ""
            pcall(function() if edit.getText() then curText = tostring(edit.getText()) end end)
            if curText ~= "" and not curText:match("%s$") then
              hasil = " " .. hasil
            end
            service.insert(edit, hasil)
          else
            service.insert(edit, hasil)
          end

          if getBool("use_auto_tts") then
            speakText(hasil)
          end

          checkAndRestart()
        end)
      else
        silenceCount = silenceCount + 1
        checkAndRestart()
      end
    end,
    onError = function(err)
      if getBool("use_continuous_mode") then
        silenceCount = silenceCount + 1
        checkAndRestart()
      else
        pesan("Gagal mendengar.")
      end
    end
  }))
  rec.startListening(intent)
end

-- ==================== LOGIKA UTAMA ====================
local edit = service.getEditText()
if edit then
  if getBool("use_revision_mode") then
    runRevision(edit)
  elseif getBool("use_confirmation") then
    local layConfirm = LinearLayout(service).setOrientation(1).setPadding(40,20,40,20)
    local btnStart = Button(service).setText("Mulai Input Suara")
    local btnRev = Button(service).setText("Revisi Teks Tersebut")
    local btnSettings = Button(service).setText("Buka Pengaturan")
    layConfirm.addView(btnStart)
    layConfirm.addView(btnRev)
    layConfirm.addView(btnSettings)

    local dlgConfirm = LuaDialog(service)
    dlgConfirm.setTitle("Pilih Tindakan")
    dlgConfirm.setView(layConfirm)
    dlgConfirm.setNegativeButton("Batal", nil)
    dlgConfirm.show()

    btnStart.setOnClickListener(function() dlgConfirm.dismiss() runSpeech(edit) end)
    btnRev.setOnClickListener(function() dlgConfirm.dismiss() runRevision(edit) end)
    btnSettings.setOnClickListener(function() dlgConfirm.dismiss() showMain() end)
  else
    runSpeech(edit)
  end
else
  showMain()
end