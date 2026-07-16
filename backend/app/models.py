import uuid
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import relationship

from .database import Base


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=lambda: new_id("user"))
    provider = Column(String, nullable=False)
    provider_id = Column(String, nullable=False)
    nickname = Column(String, nullable=False)
    profile_image = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (UniqueConstraint("provider", "provider_id", name="uq_user_provider"),)


class EditSession(Base):
    __tablename__ = "sessions"

    id = Column(String, primary_key=True, default=lambda: new_id("sess"))
    host_user_id = Column(String, ForeignKey("users.id"), nullable=False)
    invite_token = Column(String, unique=True, nullable=False, default=lambda: uuid.uuid4().hex)
    invite_code = Column(String, unique=True, nullable=False)
    status = Column(String, default="active")  # active | locked | expired
    max_members = Column(Integer, default=4)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_activity_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)

    members = relationship("Member", back_populates="session", cascade="all, delete-orphan")
    photos = relationship("Photo", back_populates="session", cascade="all, delete-orphan")


class Member(Base):
    __tablename__ = "members"

    id = Column(String, primary_key=True, default=lambda: new_id("mem"))
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    user_id = Column(String, ForeignKey("users.id"), nullable=True)
    nickname = Column(String, nullable=False)
    role = Column(String, nullable=False)  # host | guest
    connected = Column(Boolean, default=False)
    joined_at = Column(DateTime, default=datetime.utcnow)
    left_at = Column(DateTime, nullable=True)

    session = relationship("EditSession", back_populates="members")


class Photo(Base):
    __tablename__ = "photos"

    id = Column(String, primary_key=True, default=lambda: new_id("photo"))
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    url = Column(String, nullable=False)
    width = Column(Integer, default=0)
    height = Column(Integer, default=0)
    order_index = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("EditSession", back_populates="photos")
    faces = relationship("Face", back_populates="photo", cascade="all, delete-orphan")


class Face(Base):
    __tablename__ = "faces"

    id = Column(String, primary_key=True, default=lambda: new_id("face"))
    photo_id = Column(String, ForeignKey("photos.id"), nullable=False)
    face_index = Column(Integer, nullable=False)
    bbox_x = Column(Integer, default=0)
    bbox_y = Column(Integer, default=0)
    bbox_w = Column(Integer, default=0)
    bbox_h = Column(Integer, default=0)
    claimed_by_member_id = Column(String, ForeignKey("members.id"), nullable=True)

    photo = relationship("Photo", back_populates="faces")


class EditStateRecord(Base):
    __tablename__ = "edit_states"

    id = Column(String, primary_key=True, default=lambda: new_id("edit"))
    photo_id = Column(String, ForeignKey("photos.id"), unique=True, nullable=False)
    version = Column(Integer, default=0)
    global_params = Column(JSON, nullable=False)
    faces_params = Column(JSON, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow)


class EditHistory(Base):
    __tablename__ = "edit_history"

    id = Column(Integer, primary_key=True, autoincrement=True)
    photo_id = Column(String, ForeignKey("photos.id"), nullable=False)
    seq = Column(Integer, nullable=False)
    member_id = Column(String, ForeignKey("members.id"), nullable=False)
    op = Column(String, nullable=False)  # set | undo | redo
    path = Column(String, nullable=False)
    from_value = Column(JSON, nullable=True)
    to_value = Column(JSON, nullable=True)
    ts = Column(DateTime, default=datetime.utcnow)


class ExportResult(Base):
    __tablename__ = "export_results"

    id = Column(String, primary_key=True, default=lambda: new_id("export"))
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    photo_id = Column(String, ForeignKey("photos.id"), nullable=False)
    url = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
