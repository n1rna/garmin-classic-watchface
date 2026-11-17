#!/usr/bin/env python3
"""Copy a .prg onto a USB-connected Garmin watch (MTP) into GARMIN/Apps.

Needs libmtp:  brew install libmtp
Usage: python3 tools/install_to_watch.py bin/Classic.prg
"""
import ctypes, os, sys, time
from ctypes import c_uint32, c_uint64, c_char_p, c_void_p, c_int, c_long, POINTER, Structure, c_uint8
lib = ctypes.CDLL("/opt/homebrew/lib/libmtp.dylib")
class File(Structure): pass
File._fields_ = [("item_id", c_uint32), ("parent_id", c_uint32), ("storage_id", c_uint32),
                 ("filename", c_char_p), ("filesize", c_uint64), ("modificationdate", c_long),
                 ("filetype", c_int), ("next", POINTER(File))]
class Storage(Structure):
    _fields_ = [("id", c_uint32)]
class Device(Structure):
    _fields_ = [("object_bitsize", c_uint8), ("params", c_void_p), ("usbinfo", c_void_p),
                ("storage", POINTER(Storage))]
lib.LIBMTP_Init()
raw = c_void_p(); n = c_int(0)
err = lib.LIBMTP_Detect_Raw_Devices(ctypes.byref(raw), ctypes.byref(n))
lib.LIBMTP_Open_Raw_Device_Uncached.restype = POINTER(Device)
lib.LIBMTP_Open_Raw_Device_Uncached.argtypes = [c_void_p]
dev = lib.LIBMTP_Open_Raw_Device_Uncached(raw) if n.value else None
if not dev: sys.exit("No watch found - plug it in with USB (and close OpenMTP / Garmin Express).")
lib.LIBMTP_Get_Storage(dev, 0)
storage = dev.contents.storage.contents.id
src = sys.argv[1]
name = os.path.basename(src)
# find the GARMIN/Apps folder by walking the device
lib.LIBMTP_Get_Files_And_Folders.restype = POINTER(File)
lib.LIBMTP_Get_Files_And_Folders.argtypes = [POINTER(Device), c_uint32, c_uint32]
def child_id(parent_id, nm):
    f = lib.LIBMTP_Get_Files_And_Folders(dev, storage, parent_id)
    while f:
        if f.contents.filename and f.contents.filename.decode().lower() == nm:
            return f.contents.item_id
        f = f.contents.next
    return None
garmin = child_id(0xFFFFFFFF, "garmin")
parent = child_id(garmin, "apps") if garmin is not None else None
if parent is None: sys.exit("GARMIN/Apps folder not found on the watch")
# remove an existing copy with the same name in that folder
f = lib.LIBMTP_Get_Files_And_Folders(dev, storage, parent)
while f:
    if f.contents.filename and f.contents.filename.decode() == name:
        lib.LIBMTP_Delete_Object(dev, f.contents.item_id)
    f = f.contents.next
meta = File()
meta.parent_id = parent; meta.storage_id = storage
meta.filename = name.encode(); meta.filesize = os.path.getsize(src)
meta.modificationdate = int(time.time()); meta.filetype = 44  # LIBMTP_FILETYPE_UNKNOWN
lib.LIBMTP_Send_File_From_File.argtypes = [POINTER(Device), c_char_p, POINTER(File), c_void_p, c_void_p]
r = lib.LIBMTP_Send_File_From_File(dev, src.encode(), ctypes.byref(meta), None, None)
print("Installed %s on the watch." % name if r == 0 else "Copy failed.")
if r != 0: lib.LIBMTP_Dump_Errorstack(dev)
lib.LIBMTP_Release_Device(dev)
sys.exit(r)
