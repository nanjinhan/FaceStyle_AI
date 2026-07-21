"""유저 고유 색상 배정 (명세 1장 회원관리 — 고유 색상 배정).

앱의 MemberColors 팔레트(app/lib/core/theme/member_colors.dart)와 동일하게 유지한다.
가입 순서대로 팔레트를 돌려 배정하되, 이미 쓰인 색이 적은 것을 우선한다.
"""

from sqlalchemy.orm import Session

from . import models

# app/lib/core/theme/member_colors.dart 의 palette 와 1:1 대응
PALETTE = [
    "#F4573D",  # 토마토
    "#FB9E4E",  # 오렌지
    "#F7C948",  # 옐로우
    "#4CB782",  # 그린
    "#35A2C9",  # 시안
    "#5A6AE8",  # 블루
    "#9A5AE8",  # 퍼플
    "#E85A9C",  # 핑크
]


def assign_color(db: Session) -> str:
    """가장 적게 쓰인 색을 배정한다 (전체적으로 고르게 분포)."""
    counts = {c: 0 for c in PALETTE}
    for (color,) in db.query(models.User.color).filter(models.User.color.isnot(None)):
        if color in counts:
            counts[color] += 1
    # 사용 횟수 오름차순, 같으면 팔레트 순서 유지
    return min(PALETTE, key=lambda c: (counts[c], PALETTE.index(c)))
