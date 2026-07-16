from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import models, schemas, security
from ..database import get_db

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/social-login", response_model=schemas.AuthResponse)
def social_login(payload: schemas.SocialLoginRequest, db: Session = Depends(get_db)):
    """카카오/Apple/Google 로그인(AUTH-01).

    provider_token의 서명 검증은 각 OAuth 서버와의 연동이 필요한 별도 구간이며,
    이 엔드포인트는 그 검증이 클라이언트단(SDK) 또는 앞단 게이트웨이에서 이미 끝났다고
    가정하고 provider_id/nickname을 신뢰해 사용자 조회·생성만 수행한다.
    """
    user = (
        db.query(models.User)
        .filter(models.User.provider == payload.provider, models.User.provider_id == payload.provider_id)
        .first()
    )
    if user is None:
        user = models.User(
            provider=payload.provider,
            provider_id=payload.provider_id,
            nickname=payload.nickname,
            profile_image=payload.profile_image,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    token = security.create_user_token(user.id)
    return schemas.AuthResponse(access_token=token, user=schemas.UserOut.model_validate(user))


@router.get("/me", response_model=schemas.UserOut)
def me(current_user: models.User = Depends(security.get_current_user)):
    return current_user
