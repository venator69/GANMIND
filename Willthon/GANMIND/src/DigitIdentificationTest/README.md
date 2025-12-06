# DigitIdentificationTest

Testbench dan utilitas ini memvalidasi alur *digit identifier* GANMIND dengan
menggunakan salah satu sampel citra yang sudah ada pada folder `samples/`. Semua
artefak disimpan di dalam `src/DigitIdentificationTest` agar mudah dilacak dan
para pemakai dapat meregenerasi fixture tanpa keluar dari repo.

## Isi folder
- `digit_identifier_tb.v` – testbench utama yang menginstansiasi `gan_serial_top`,
  melakukan streaming piksel 28x28, dan menulis keluaran GAN ke mem file.
- `digit_sample_tools.py` – helper berbasis Pillow untuk mengubah PNG/JPG menjadi
  file `.mem` Q8.8 ataupun sebaliknya.
- `digit_identifier_sample.mem` – fixture default yang dihasilkan dari
  `samples/real_images.png` menggunakan helper di atas.
- `../CombinationalDone/combinational_done_block.v` – blok ROM kombinational yang
  menghamparkan data sample/expected ke bus lebar untuk validasi tanpa serialisasi.
- `../CombinationalDone/gan_comb_top.v` – wrapper top-level yang otomatis
  men-streaming-kan piksel dari blok ROM ke `gan_serial_top` tanpa stimulus
  testbench manual.
- `../CombinationalDone/gan_comb_frame_top.v` – varian `gan_comb_top` yang
  menerima frame 28x28 dalam bentuk bus lebar (`sample_flat`) sehingga bisa
  dihubungkan langsung dengan fixture eksternal tanpa memuat file `.mem`.

## Menyiapkan sampel digit
```powershell
# Opsional: normalisasi histogram dan tentukan ROI jika ingin fokus area tertentu
python Willthon/GANMIND/src/DigitIdentificationTest/digit_sample_tools.py `
    from-image `
    --image Willthon/GANMIND/samples/real_images.png `
    --mem Willthon/GANMIND/src/DigitIdentificationTest/digit_identifier_sample.mem `
    --normalize
```

Parameter penting:
- `--roi left,top,width,height` memakai koordinat relatif (0-1) terhadap gambar
  sumber jika ingin memotong grid.
- `--preview path/to/png` dapat dipakai untuk melihat hasil downsample 28x28.
- Subperintah `to-image` tersedia untuk mengecek `.mem` menjadi PNG kembali.

## Menjalankan testbench
```powershell
mkdir build -ErrorAction SilentlyContinue
iverilog -g2012 `
  -I Willthon/GANMIND/src/top `
  -I Willthon/GANMIND/src/interfaces `
  -I Willthon/GANMIND/src/layers `
  -o build/digit_identifier_tb.vvp `
  Willthon/GANMIND/src/DigitIdentificationTest/digit_identifier_tb.v `
  Willthon/GANMIND/src/top/gan_serial_top.v
vvp build/digit_identifier_tb.vvp           # tambah +dumpvcd bila perlu gelombang
```

Output utama:
- `digit_identifier_generated.mem` – frame hasil generator dalam format Q8.8.
- `digit_identifier_metrics.log` – ringkasan skor diskriminator dan statistik
  selisih rata-rata/maks antar piksel.
- `vcd/digit_identifier_tb.vcd` – gelombang untuk dianalisis di GTKWave (aktifkan
  dengan menambahkan `+dumpvcd` saat menjalankan `vvp`).

Testbench akan mem-fail apabila:
1. `gan_serial_top` tidak pernah menyelesaikan pekerjaan (timeout 200k siklus),
2. discriminator menandai sampel real sebagai palsu, atau
3. file output tidak dapat ditulis.

Dengan setup ini, Anda dapat dengan cepat menyiapkan fixture baru dari `samples`
dan memverifikasi apakah jalur digit identifier menghasilkan representasi yang
layak untuk pipeline berikutnya.

## Validasi kombinational
Folder `src/CombinationalDone` memuat `combinational_done_block.v` yang membaca
`digit_identifier_sample.mem` (dan opsional `digit_identifier_expected.mem` jika
tersedia) lalu menyajikan seluruh 784 kata sekaligus. Testbench otomatis
menunggu blok ini siap sebelum streaming piksel dan akan mem-fail jika file
expected ditemukan tetapi isinya tidak cocok dengan hasil GAN. Untuk membuat
snapshot expected baru cukup simpan file Q8.8 bernama
`src/DigitIdentificationTest/digit_identifier_expected.mem` sebelum menjalankan
simulasi.

Jika file expected belum ada, `digit_identifier_tb` akan otomatis menulis
`digit_identifier_generated.mem` ke jalur expected setelah run pertama selesai.
Snapshot tersebut baru digunakan pada eksekusi berikutnya, jadi cukup jalankan
simulasi dua kali saat pertama kali menyiapkan fixture baru.

Untuk integrasi di luar testbench ini terdapat dua opsi:
1. `gan_comb_top` – membaca `digit_identifier_sample.mem`, melakukan serialisasi
  sendiri, cocok bagi pengguna yang ingin langsung menjalankan pipeline dengan
  fixture bawaan repo.
2. `gan_comb_frame_top` – menerima `sample_flat` dan sinyal `sample_valid`
  langsung dari lingkungan eksternal. Modul ini mengurus serialisasi internal
  dan memicu `gan_serial_top`, sehingga cukup menyalin data 28x28 lalu memberi
  pulsa `start`.

Apabila ingin menjalankan seluruh alur tanpa testbench terpisah, gunakan
`gan_comb_top.v`. Modul tersebut menginstansiasi ROM kombinational, melakukan
serialisasi piksel secara internal, menunggu `frame_ready`, dan men-trigger
`gan_serial_top` menggunakan sinyal `start`. Contoh integrasi cepat:

```verilog
gan_comb_top u_top (
  .clk(clk),
  .rst(rst),
  .start(run_one_sample),
  .busy(),
  .done(sample_done)
  // tangkap juga disc_* / generated_frame_flat jika diperlukan
);
```

Dengan demikian Anda bisa memasukkan blok ini langsung ke lingkungan verifikasi
lain (mis. top-level SoC testbench) cukup dengan memberikan pulsa `start` dan
memonitor sinyal `done` atau `generated_frame_valid`.
