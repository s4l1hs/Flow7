"""add language to user_settings

Revision ID: 0002_add_language
Revises: 0001_initial
Create Date: 2025-10-26 00:30:00.000000
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0002_add_language'
down_revision = '0001_initial'
branch_labels = None
depends_on = None


def upgrade():
    # Add nullable language column to user_settings for i18n preference
    op.add_column('user_settings', sa.Column('language', sa.String(), nullable=True))


def downgrade():
    op.drop_column('user_settings', 'language')

