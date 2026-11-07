#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 6.4 真机验收用的 .memoir 测试包变体（docs/harmony-spec/10_BUILD_MANUAL.md 6.4）。

以一个真实导出包（默认取 iOS 样本包）为底子，产出：
  1) 尺素备份_重放.memoir    —— 原包原样（重复导入应全部跳过）
  2) 尺素备份_v2.memoir      —— manifest.formatVersion = 2（应拒收）
  3) 尺素备份_缺图.memoir    —— media/ 清空但引用还在（应导入成功 + 缺图警告）
  4) 尺素备份_坏包.memoir    —— manifest.json 损坏（应打开失败 toast）
  5) 尺素备份_加密.memoir    —— 头 + PBKDF2(210000) + AES-256-GCM 加密，
                                密码 1234（需 python cryptography 库；没有则跳过，
                                加密验收改走「鸿蒙导出 → 鸿蒙导入」自闭环 + iOS 互导）

用法：python3 scripts/make_backup_test_packages.py [样本包路径] [输出目录]
"""
import io
import json
import os
import shutil
import sys
import tempfile
import zipfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

PASSWORD = '1234'
MAGIC = b'MEMOIRBK'
HEADER_VER = 1
HEADER_FLAG = 0x01
SALT_LEN = 16
NONCE_LEN = 12
PBKDF2_ITERATIONS = 210000
KEY_LEN = 32


def find_root(unpack_dir):
    """manifest.json 在顶层或一层子目录（与 BackupImportService.findPackageRoot 口径一致）。"""
    if os.path.isfile(os.path.join(unpack_dir, 'manifest.json')):
        return unpack_dir
    for name in sorted(os.listdir(unpack_dir)):
        if name.startswith('__MACOSX') or name.startswith('.'):
            continue
        candidate = os.path.join(unpack_dir, name)
        if os.path.isfile(os.path.join(candidate, 'manifest.json')):
            return candidate
    raise SystemExit('样本包里找不到 manifest.json')


def rezip(root, out_path):
    """把 root 目录打成标准 zip（与 iOS 导出口径一致：顶层就是包内容）。"""
    if os.path.exists(out_path):
        os.remove(out_path)
    with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            for filename in sorted(filenames):
                full = os.path.join(dirpath, filename)
                zf.write(full, os.path.relpath(full, root))


def load_manifest(root):
    with io.open(os.path.join(root, 'manifest.json'), encoding='utf-8') as f:
        return json.load(f)


def save_manifest(root, manifest):
    with io.open(os.path.join(root, 'manifest.json'), 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)


def encrypt_file(plain_path, out_path):
    """整体加密（与 BackupCrypto.ets / BackupCrypto.swift 逐字节一致）。"""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM  # noqa: F401
    import hashlib
    import secrets
    salt = secrets.token_bytes(SALT_LEN)
    nonce = secrets.token_bytes(NONCE_LEN)
    key = hashlib.pbkdf2_hmac('sha256', PASSWORD.encode('utf-8'), salt,
                              PBKDF2_ITERATIONS, KEY_LEN)
    with open(plain_path, 'rb') as f:
        plaintext = f.read()
    sealed = AESGCM(key).encrypt(nonce, plaintext, b'')
    header = MAGIC + bytes([HEADER_VER, HEADER_FLAG]) + salt + nonce
    with open(out_path, 'wb') as f:
        f.write(header + sealed)


def main():
    sample = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.expanduser('~/Downloads/尺素备份_20260812.memoir')
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(sample) or '.'
    if not os.path.isfile(sample):
        raise SystemExit('样本包不存在: %s' % sample)
    os.makedirs(outdir, exist_ok=True)

    def fresh_root(work):
        """干净解包 → 包根目录。每个变体独立解，改动不互相污染。"""
        if os.path.exists(work):
            shutil.rmtree(work)
        os.makedirs(work)
        with zipfile.ZipFile(sample) as zf:
            zf.extractall(work)
        return find_root(work)

    # 1) 重放：原样（重复导入应全跳过）
    replay = os.path.join(outdir, '尺素备份_重放.memoir')
    shutil.copyfile(sample, replay)
    print('OK 1/5 重放包         %s' % replay)

    work = tempfile.mkdtemp(prefix='memoir-pkg-')
    try:
        # 2) v2：formatVersion 改 2（应拒收）
        root = fresh_root(work)
        save_manifest(root, dict(load_manifest(root), formatVersion=2))
        v2 = os.path.join(outdir, '尺素备份_v2.memoir')
        rezip(root, v2)
        print('OK 2/5 v2 拒收包      %s' % v2)

        # 3) 缺图：清空 media/ 但引用留在 entries 里（应导入成功 + 缺图警告）
        root = fresh_root(work)
        media_dir = os.path.join(root, 'media')
        if os.path.isdir(media_dir):
            for name in os.listdir(media_dir):
                os.remove(os.path.join(media_dir, name))
        missing = os.path.join(outdir, '尺素备份_缺图.memoir')
        rezip(root, missing)
        print('OK 3/5 缺图包         %s' % missing)

        # 4) 坏包：manifest.json 写坏（应打开失败 toast）
        root = fresh_root(work)
        with io.open(os.path.join(root, 'manifest.json'), 'w', encoding='utf-8') as f:
            f.write('{"formatVersion": 1, oops')
        broken = os.path.join(outdir, '尺素备份_坏包.memoir')
        rezip(root, broken)
        print('OK 4/5 坏包           %s' % broken)

        # 5) 加密：干净内容整体加密（与 BackupCrypto 布局逐字节一致）
        root = fresh_root(work)
        plain_zip = os.path.join(work, 'plain.zip')
        rezip(root, plain_zip)
        encrypted = os.path.join(outdir, '尺素备份_加密.memoir')
        try:
            encrypt_file(plain_zip, encrypted)
            print('OK 5/5 加密包（密码 %s） %s' % (PASSWORD, encrypted))
        except ImportError:
            print('跳过 5/5 加密包：缺 python cryptography 库'
                  '（pip3 install cryptography）；加密验收走鸿蒙自闭环 + iOS 互导')
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
