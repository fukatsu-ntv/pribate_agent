"""NTV 経理エージェントが扱う固定用語の Python 定義。

`docs/keiri-readme.md` および `keiri/docs/用語集.md` と同期させること。
仕様変更があった場合は両方更新。
"""

from __future__ import annotations

from enum import Enum


class ShoriKubun(str, Enum):
    """処理区分。「処理」列に入力される値。"""

    GAISAN = "概算"
    X_GAI = "X概"
    GAISHO = "概処"
    JITSU_GAI = "実概"
    JITSU_DEN = "実伝"


class GyomuTanniCode(str, Enum):
    """業務単位コード。エージェントが編集対象とするのは EDITABLE のみ。"""

    AI_JIGYO = "11Y5471"  # AI 事業 (びっくりあいらんど) — 編集可
    NEWS_HAISHIN = "11Y5818"  # ニュース配信 — 参照のみ


EDITABLE_CODES: frozenset[str] = frozenset({GyomuTanniCode.AI_JIGYO.value})


SHUNYU_HIMOKU: tuple[str, ...] = (
    "外販",
    "オウンド広告",
)


HIYO_HIMOKU: tuple[str, ...] = (
    "NNN分配費等",
    "SaaS・ツール利用費",
    "カルチャーDIV人件費",
    "コンサル委託費等",
    "コンテンツ制作費",
    "コンテンツ利用費",
    "デジタルG人件費",
    "記事・テロップ制作・校閲",
    "広告・営業費合計",
    "雑費",
    "設備・システム費",
    "総合編成人件費",
    "報道スポーツ費",
    "出演費",
)


ALL_HIMOKU: frozenset[str] = frozenset(SHUNYU_HIMOKU + HIYO_HIMOKU)


def is_known_himoku(name: str) -> bool:
    """既知の費目かどうか。新規費目はユーザー承認が必須。"""
    return name in ALL_HIMOKU


def is_editable_code(code: str) -> bool:
    """業務単位コードが編集可能か。"""
    return code in EDITABLE_CODES
