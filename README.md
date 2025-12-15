# stream-chunk-backup

Streaming, chunked backups for very large directories on low-disk systems.

Designed for Mail-in-a-Box (MIAB), object-storage mounts (Garage / S3 / rclone / FUSE), and servers where **local disk space is limited**.

---

## ✨ What this tool does

`stream-chunk-backup`:

- Streams directories into a **TAR archive**
- Splits the stream into **fixed-size chunks** (default: 5 GB)
- Writes chunks **directly to the destination**
- **Never stores full archives locally**
- Shows **real-time throughput and ETA**
- Works reliably with **S3-backed / FUSE filesystems**

Each source directory becomes a set of numbered archive parts that can later be reassembled and restored.

---

## ❓ Why this exists

Traditional tools fail in this scenario:

| Tool | Why it fails |
|----|----|
| `zip` | Requires full directory indexing; not stream-safe |
| `rsync` | Uses temp files, renames, symlinks → breaks on FUSE/S3 |
| `tar` (alone) | Creates one huge file → no chunking |

This project uses the **only safe pattern** for large, low-disk, object-storage backups:

```
tar → pv → split → cat
```

---

## 📦 Output structure

```
DEST_BASE/
  user-data/
    user-data.tar.part_001
    user-data.tar.part_002
    ...
  disk1/
    disk1.tar.part_001
    ...
```

---

## 🔧 Requirements

- Linux
- bash
- tar
- split (coreutils)
- pv

Install pv if missing:

```
sudo apt install -y pv
```

---

## 🚀 Usage

### CLI example

```
sudo ./stream_chunk_backup.sh \
  --dest /mnt/garage/Backups/MIAB \
  --src /home/user-data \
  --src /mnt/disk1
```

### Config file usage

```
sudo ./stream_chunk_backup.sh --config backup.conf
```

---

## ⚙️ Example backup.conf

```
DEST_BASE="/mnt/garage/Backups/MIAB"
CHUNK_SIZE="5G"
LOGFILE="/var/log/stream_chunk_backup.log"

SRC_DIRS=(
  "/home/user-data"
  "/mnt/disk1"
)
```

---

## 🔄 Restore

```
cat user-data.tar.part_* | tar -xpf -
```

---

## 📜 License

MIT
