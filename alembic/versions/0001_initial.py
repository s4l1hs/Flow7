"""initial

Revision ID: 0001_initial
Revises: 
Create Date: 2025-10-26 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0001_initial'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # plans table
    op.create_table(
        'plans',
        sa.Column('id', sa.String(), primary_key=True),
        sa.Column('user_id', sa.String(), nullable=False, index=True),
        sa.Column('date', sa.Date(), nullable=False, index=True),
        sa.Column('start_time', sa.Time(), nullable=False),
        sa.Column('end_time', sa.Time(), nullable=False),
        sa.Column('title', sa.String(), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('notified', sa.Boolean(), nullable=False, server_default=sa.text('0')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
    )

    # user_settings table
    op.create_table(
        'user_settings',
        sa.Column('uid', sa.String(), primary_key=True),
        sa.Column('level', sa.String(), nullable=True),
        sa.Column('theme', sa.String(), nullable=True),
        sa.Column('timezone', sa.String(), nullable=True),
        sa.Column('country', sa.String(), nullable=True),
        sa.Column('city', sa.String(), nullable=True),
        sa.Column('notifications_enabled', sa.Boolean(), nullable=True, server_default=sa.text('1')),
    )

    # device_tokens table
    op.create_table(
        'device_tokens',
        sa.Column('token', sa.String(), primary_key=True),
        sa.Column('user_id', sa.String(), nullable=False, index=True),
        sa.Column('provider', sa.String(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
    )

    # APScheduler jobs table (simple schema)
    op.create_table(
        'apscheduler_jobs',
        sa.Column('id', sa.String(length=191), primary_key=True),
        sa.Column('next_run_time', sa.Float(), nullable=True),
        sa.Column('job_state', sa.LargeBinary(), nullable=False),
    )


def downgrade():
    op.drop_table('apscheduler_jobs')
    op.drop_table('device_tokens')
    op.drop_table('user_settings')
    op.drop_table('plans')
