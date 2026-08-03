import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { broadcastNotification, sendDirectNotification, getFcmStatus } from '../api/client';
import { Megaphone, Send, Smartphone, ShieldCheck, Users, RefreshCw, Bell, UserCheck, AlertTriangle, Info, CheckCircle2 } from 'lucide-react';
import CustomSelect from '../components/CustomSelect';

const AUDIENCE_OPTIONS = [
  { value: 'all', label: '📢 All Users (Global Broadcast)' },
  { value: 'passenger', label: '📱 Passengers Only' },
  { value: 'owner', label: '🚍 Bus Owners Only' },
  { value: 'conductor', label: '🎫 Conductors Only' },
  { value: 'admin', label: '⚡ Admins Only' },
];

const PRESETS = [
  {
    title: '🎉 Welcome to Seaty!',
    message: 'Book your luxury bus tickets with real-time seat tracking and instant booking updates on Seaty.',
    role: 'passenger',
  },
  {
    title: '⚠️ Scheduled System Maintenance',
    message: 'Seaty platform services will undergo routine maintenance tonight at 2:00 AM for 15 minutes.',
    role: 'all',
  },
  {
    title: '🚌 New Route Announcement',
    message: 'Exciting news! New express highway routes from Colombo to Galle are now open for booking.',
    role: 'passenger',
  },
  {
    title: '📋 Conductor Duty Reminder',
    message: 'Please review your assigned trip schedules for today and ensure GPS tracking is active before departure.',
    role: 'conductor',
  },
];

interface FcmStatusData {
  firebase_credentials_env?: string;
  firebase_credentials_file_exists?: boolean;
  total_users?: number;
  users_with_fcm_token?: number;
  users_without_fcm_token?: number;
  users_detail?: Array<{ id: string; name: string; role: string; has_fcm_token: boolean }>;
}

export default function NotificationsPage() {
  const { token } = useAuth();
  const [activeTab, setActiveTab] = useState<'broadcast' | 'direct' | 'status'>('broadcast');

  // Broadcast state
  const [broadcastTitle, setBroadcastTitle] = useState('');
  const [broadcastMessage, setBroadcastMessage] = useState('');
  const [targetRole, setTargetRole] = useState('all');
  const [sendingBroadcast, setSendingBroadcast] = useState(false);
  const [broadcastSuccess, setBroadcastSuccess] = useState<string | null>(null);
  const [broadcastError, setBroadcastError] = useState<string | null>(null);

  // Direct Push state
  const [directPhone, setDirectPhone] = useState('');
  const [directTitle, setDirectTitle] = useState('');
  const [directMessage, setDirectMessage] = useState('');
  const [sendingDirect, setSendingDirect] = useState(false);
  const [directSuccess, setDirectSuccess] = useState<string | null>(null);
  const [directError, setDirectError] = useState<string | null>(null);

  // FCM Status state
  const [fcmStatus, setFcmStatus] = useState<FcmStatusData | null>(null);
  const [loadingStatus, setLoadingStatus] = useState(false);

  const fetchStatus = async () => {
    if (!token) return;
    setLoadingStatus(true);
    try {
      const data = await getFcmStatus(token) as FcmStatusData;
      setFcmStatus(data);
    } catch {
      setFcmStatus(null);
    } finally {
      setLoadingStatus(false);
    }
  };

  useEffect(() => {
    fetchStatus();
  }, [token]);

  const handleBroadcastSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !broadcastTitle.trim() || !broadcastMessage.trim()) return;

    setSendingBroadcast(true);
    setBroadcastSuccess(null);
    setBroadcastError(null);

    try {
      const response = await broadcastNotification(token, broadcastTitle, broadcastMessage, targetRole) as { message: string };
      setBroadcastSuccess(response.message || 'Push notification broadcast successfully dispatched!');
      setBroadcastTitle('');
      setBroadcastMessage('');
      fetchStatus();
    } catch (err) {
      setBroadcastError(err instanceof Error ? err.message : 'Failed to send broadcast');
    } finally {
      setSendingBroadcast(false);
    }
  };

  const handleDirectSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !directPhone.trim() || !directTitle.trim() || !directMessage.trim()) return;

    setSendingDirect(true);
    setDirectSuccess(null);
    setDirectError(null);

    try {
      const response = await sendDirectNotification(token, {
        phone_number: directPhone.trim(),
        title: directTitle.trim(),
        message: directMessage.trim(),
      }) as { message: string };

      setDirectSuccess(response.message || 'Push notification delivered directly to user device!');
      setDirectPhone('');
      setDirectTitle('');
      setDirectMessage('');
      fetchStatus();
    } catch (err) {
      setDirectError(err instanceof Error ? err.message : 'Failed to send direct notification');
    } finally {
      setSendingDirect(false);
    }
  };

  const loadPreset = (p: typeof PRESETS[0]) => {
    setBroadcastTitle(p.title);
    setBroadcastMessage(p.message);
    setTargetRole(p.role);
  };

  return (
    <div>
      {/* Page Header */}
      <div className="page-header">
        <div>
          <h1 className="page-title">Push Notification Center</h1>
          <p className="page-subtitle">
            Dispatch real-time FCM push notifications to iOS and Android devices by user role or individual phone numbers.
          </p>
        </div>
        <button
          onClick={fetchStatus}
          className="btn-action btn-action-success"
          style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
        >
          <RefreshCw size={14} className={loadingStatus ? 'animate-spin' : ''} /> Refresh Status
        </button>
      </div>

      {/* Navigation Tabs */}
      <div
        style={{
          display: 'flex',
          gap: '8px',
          margin: '20px 0',
          borderBottom: '1px solid var(--border-color)',
          paddingBottom: '12px',
        }}
      >
        <button
          onClick={() => setActiveTab('broadcast')}
          style={{
            padding: '10px 18px',
            borderRadius: '10px',
            border: activeTab === 'broadcast' ? '1px solid var(--color-primary)' : '1px solid transparent',
            background: activeTab === 'broadcast' ? 'rgba(37, 99, 235, 0.08)' : 'transparent',
            color: activeTab === 'broadcast' ? 'var(--color-primary)' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '13.5px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            transition: 'all 0.2s ease',
          }}
        >
          <Megaphone size={16} /> Role Broadcast
        </button>

        <button
          onClick={() => setActiveTab('direct')}
          style={{
            padding: '10px 18px',
            borderRadius: '10px',
            border: activeTab === 'direct' ? '1px solid var(--color-primary)' : '1px solid transparent',
            background: activeTab === 'direct' ? 'rgba(37, 99, 235, 0.08)' : 'transparent',
            color: activeTab === 'direct' ? 'var(--color-primary)' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '13.5px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            transition: 'all 0.2s ease',
          }}
        >
          <UserCheck size={16} /> Direct User Push
        </button>

        <button
          onClick={() => setActiveTab('status')}
          style={{
            padding: '10px 18px',
            borderRadius: '10px',
            border: activeTab === 'status' ? '1px solid var(--color-primary)' : '1px solid transparent',
            background: activeTab === 'status' ? 'rgba(37, 99, 235, 0.08)' : 'transparent',
            color: activeTab === 'status' ? 'var(--color-primary)' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '13.5px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            transition: 'all 0.2s ease',
          }}
        >
          <ShieldCheck size={16} /> FCM Health & Stats
        </button>
      </div>

      {/* Main Grid Content */}
      {activeTab === 'broadcast' && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(420px, 1fr))', gap: '24px', alignItems: 'start' }}>
          {/* Left: Broadcast Form */}
          <div className="table-card" style={{ margin: 0 }}>
            <h3 className="table-title" style={{ marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Megaphone size={18} style={{ color: '#2563eb' }} /> Compose Role Broadcast
            </h3>
            <p className="page-subtitle" style={{ marginBottom: '20px' }}>
              Target specific user groups or dispatch a global announcement across all registered devices.
            </p>

            {broadcastSuccess && (
              <div
                className="badge badge-success"
                style={{
                  width: '100%',
                  marginBottom: '16px',
                  padding: '12px 14px',
                  borderRadius: '10px',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  justifyContent: 'center',
                }}
              >
                <CheckCircle2 size={16} /> {broadcastSuccess}
              </div>
            )}

            {broadcastError && (
              <div
                className="badge badge-danger"
                style={{
                  width: '100%',
                  marginBottom: '16px',
                  padding: '12px 14px',
                  borderRadius: '10px',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  justifyContent: 'center',
                }}
              >
                <AlertTriangle size={16} /> {broadcastError}
              </div>
            )}

            {/* Quick Templates Presets */}
            <div style={{ marginBottom: '20px' }}>
              <label style={{ fontSize: '11px', textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 700, color: 'var(--text-muted)', display: 'block', marginBottom: '8px' }}>
                ⚡ Quick Presets
              </label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                {PRESETS.map((p, i) => (
                  <button
                    key={i}
                    type="button"
                    onClick={() => loadPreset(p)}
                    style={{
                      padding: '5px 10px',
                      borderRadius: '6px',
                      border: '1px solid var(--border-color)',
                      background: 'var(--bg-secondary)',
                      fontSize: '12px',
                      fontWeight: 600,
                      color: 'var(--text-dark)',
                      cursor: 'pointer',
                      transition: 'all 0.15s ease',
                    }}
                    onMouseEnter={e => (e.currentTarget.style.borderColor = '#2563eb')}
                    onMouseLeave={e => (e.currentTarget.style.borderColor = 'var(--border-color)')}
                  >
                    {p.title}
                  </button>
                ))}
              </div>
            </div>

            <form onSubmit={handleBroadcastSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Target Audience Role</label>
                <CustomSelect
                  options={AUDIENCE_OPTIONS}
                  value={targetRole}
                  onChange={val => setTargetRole(val)}
                  style={{ width: '100%' }}
                />
              </div>

              <div className="form-group" style={{ marginBottom: 0 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <label className="form-label">Notification Title</label>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{broadcastTitle.length} chars</span>
                </div>
                <input
                  type="text"
                  className="form-input"
                  placeholder="e.g. Welcome to Seaty!"
                  value={broadcastTitle}
                  onChange={e => setBroadcastTitle(e.target.value)}
                  required
                />
              </div>

              <div className="form-group" style={{ marginBottom: 0 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <label className="form-label">Message Content</label>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{broadcastMessage.length} chars</span>
                </div>
                <textarea
                  className="form-input"
                  placeholder="Enter the push notification body details..."
                  rows={4}
                  value={broadcastMessage}
                  onChange={e => setBroadcastMessage(e.target.value)}
                  style={{ resize: 'vertical' }}
                  required
                />
              </div>

              <button
                type="submit"
                disabled={sendingBroadcast || !broadcastTitle.trim() || !broadcastMessage.trim()}
                style={{
                  padding: '13px',
                  border: 'none',
                  borderRadius: '10px',
                  background: broadcastTitle.trim() && broadcastMessage.trim() && !sendingBroadcast ? '#2563eb' : '#e2e8f0',
                  color: broadcastTitle.trim() && broadcastMessage.trim() && !sendingBroadcast ? 'white' : '#94a3b8',
                  cursor: broadcastTitle.trim() && broadcastMessage.trim() && !sendingBroadcast ? 'pointer' : 'default',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '8px',
                  fontSize: '14px',
                  fontWeight: 700,
                  boxShadow: broadcastTitle.trim() && broadcastMessage.trim() && !sendingBroadcast ? '0 4px 14px rgba(37, 99, 235, 0.25)' : 'none',
                  transition: 'all 0.2s ease',
                  marginTop: '8px',
                }}
              >
                <Send size={16} /> {sendingBroadcast ? 'Broadcasting Push...' : 'Send Broadcast Push'}
              </button>
            </form>
          </div>

          {/* Right: Live Interactive Mockup */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
            <div className="table-card" style={{ margin: 0, background: 'linear-gradient(135deg, #1e293b, #0f172a)', color: 'white' }}>
              <h3 style={{ fontSize: '15px', fontWeight: 700, marginBottom: '14px', display: 'flex', alignItems: 'center', gap: '8px', color: '#93c5fd' }}>
                <Smartphone size={18} /> Live Device Lock Screen Preview
              </h3>

              <div
                style={{
                  background: 'rgba(255, 255, 255, 0.08)',
                  backdropFilter: 'blur(16px)',
                  borderRadius: '16px',
                  padding: '16px',
                  border: '1px solid rgba(255, 255, 255, 0.12)',
                  boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3)',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '8px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <div style={{ width: '20px', height: '20px', borderRadius: '6px', background: '#2563eb', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 800, fontSize: '11px' }}>
                      S
                    </div>
                    <span style={{ fontSize: '12px', fontWeight: 700, color: '#e2e8f0', letterSpacing: '0.02em' }}>SEATY</span>
                  </div>
                  <span style={{ fontSize: '11px', color: '#94a3b8' }}>now</span>
                </div>

                <div style={{ fontSize: '13.5px', fontWeight: 700, color: '#f8fafc', marginBottom: '4px' }}>
                  {broadcastTitle.trim() || 'Notification Title Preview'}
                </div>
                <div style={{ fontSize: '12.5px', color: '#cbd5e1', lineHeight: '1.4' }}>
                  {broadcastMessage.trim() || 'Your push notification message content will appear here on user lock screens.'}
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '16px', fontSize: '11px', color: '#94a3b8' }}>
                <span>Target: <strong>{AUDIENCE_OPTIONS.find(o => o.value === targetRole)?.label}</strong></span>
                <span>FCM Engine: <strong>Active</strong></span>
              </div>
            </div>

            {/* Quick Stats Summary */}
            <div className="table-card" style={{ margin: 0 }}>
              <h3 className="table-title" style={{ marginBottom: '14px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Users size={16} style={{ color: '#2563eb' }} /> Audience Coverage Stats
              </h3>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div style={{ background: 'var(--bg-secondary)', padding: '12px', borderRadius: '10px', border: '1px solid var(--border-color)' }}>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>Total Registered</span>
                  <div style={{ fontSize: '20px', fontWeight: 800, color: 'var(--text-dark)', marginTop: '2px' }}>
                    {fcmStatus?.total_users ?? '...'}
                  </div>
                </div>
                <div style={{ background: 'rgba(37, 99, 235, 0.06)', padding: '12px', borderRadius: '10px', border: '1px solid rgba(37, 99, 235, 0.15)' }}>
                  <span style={{ fontSize: '11px', color: 'var(--color-primary)', fontWeight: 600 }}>FCM Push Ready</span>
                  <div style={{ fontSize: '20px', fontWeight: 800, color: 'var(--color-primary)', marginTop: '2px' }}>
                    {fcmStatus?.users_with_fcm_token ?? '...'}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Direct User Push */}
      {activeTab === 'direct' && (
        <div style={{ maxWidth: '650px', margin: '0 auto' }}>
          <div className="table-card" style={{ margin: 0 }}>
            <h3 className="table-title" style={{ marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <UserCheck size={18} style={{ color: '#2563eb' }} /> Send Direct Push Notification
            </h3>
            <p className="page-subtitle" style={{ marginBottom: '20px' }}>
              Target an individual user by entering their registered phone number (e.g. 0756371472 or +94756371472).
            </p>

            {directSuccess && (
              <div className="badge badge-success" style={{ width: '100%', marginBottom: '16px', padding: '12px 14px', borderRadius: '10px', display: 'flex', alignItems: 'center', gap: '8px', justifyContent: 'center' }}>
                <CheckCircle2 size={16} /> {directSuccess}
              </div>
            )}

            {directError && (
              <div className="badge badge-danger" style={{ width: '100%', marginBottom: '16px', padding: '12px 14px', borderRadius: '10px', display: 'flex', alignItems: 'center', gap: '8px', justifyContent: 'center' }}>
                <AlertTriangle size={16} /> {directError}
              </div>
            )}

            <form onSubmit={handleDirectSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Recipient Phone Number</label>
                <input
                  type="text"
                  className="form-input"
                  placeholder="e.g. 0756371472"
                  value={directPhone}
                  onChange={e => setDirectPhone(e.target.value)}
                  required
                />
              </div>

              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Notification Title</label>
                <input
                  type="text"
                  className="form-input"
                  placeholder="e.g. Trip Update or Urgent Notice"
                  value={directTitle}
                  onChange={e => setDirectTitle(e.target.value)}
                  required
                />
              </div>

              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Notification Message</label>
                <textarea
                  className="form-input"
                  placeholder="Enter details of message..."
                  rows={4}
                  value={directMessage}
                  onChange={e => setDirectMessage(e.target.value)}
                  style={{ resize: 'vertical' }}
                  required
                />
              </div>

              <button
                type="submit"
                disabled={sendingDirect || !directPhone.trim() || !directTitle.trim() || !directMessage.trim()}
                style={{
                  padding: '13px',
                  border: 'none',
                  borderRadius: '10px',
                  background: directPhone.trim() && directTitle.trim() && directMessage.trim() && !sendingDirect ? '#2563eb' : '#e2e8f0',
                  color: directPhone.trim() && directTitle.trim() && directMessage.trim() && !sendingDirect ? 'white' : '#94a3b8',
                  cursor: directPhone.trim() && directTitle.trim() && directMessage.trim() && !sendingDirect ? 'pointer' : 'default',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '8px',
                  fontSize: '14px',
                  fontWeight: 700,
                  boxShadow: directPhone.trim() && directTitle.trim() && directMessage.trim() && !sendingDirect ? '0 4px 14px rgba(37, 99, 235, 0.25)' : 'none',
                  transition: 'all 0.2s ease',
                  marginTop: '8px',
                }}
              >
                <Send size={16} /> {sendingDirect ? 'Sending Notification...' : 'Send Direct Push Notification'}
              </button>
            </form>
          </div>
        </div>
      )}

      {/* Tab 3: FCM Health & Registered Users List */}
      {activeTab === 'status' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          {/* Health Box */}
          <div className="table-card" style={{ margin: 0 }}>
            <h3 className="table-title" style={{ marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <ShieldCheck size={18} style={{ color: '#2563eb' }} /> Firebase Admin SDK Credentials Status
            </h3>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '16px' }}>
              <div style={{ padding: '14px', background: 'var(--bg-secondary)', borderRadius: '10px', border: '1px solid var(--border-color)' }}>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>Credentials Path Env</span>
                <div style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-dark)', marginTop: '4px', wordBreak: 'break-all' }}>
                  {fcmStatus?.firebase_credentials_env || 'GOOGLE_APPLICATION_CREDENTIALS'}
                </div>
              </div>

              <div style={{ padding: '14px', background: 'var(--bg-secondary)', borderRadius: '10px', border: '1px solid var(--border-color)' }}>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>Service Account File</span>
                <div style={{ marginTop: '4px' }}>
                  {fcmStatus?.firebase_credentials_file_exists ? (
                    <span className="badge badge-success" style={{ padding: '4px 10px' }}>Loaded & Valid</span>
                  ) : (
                    <span className="badge badge-warning" style={{ padding: '4px 10px' }}>Checking...</span>
                  )}
                </div>
              </div>

              <div style={{ padding: '14px', background: 'var(--bg-secondary)', borderRadius: '10px', border: '1px solid var(--border-color)' }}>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>Active FCM Push Devices</span>
                <div style={{ fontSize: '16px', fontWeight: 800, color: '#16a34a', marginTop: '4px' }}>
                  {fcmStatus?.users_with_fcm_token ?? 0} / {fcmStatus?.total_users ?? 0} Users
                </div>
              </div>
            </div>
          </div>

          {/* User FCM Tokens Table */}
          <div className="table-card" style={{ margin: 0 }}>
            <h3 className="table-title" style={{ marginBottom: '14px', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Bell size={18} style={{ color: '#2563eb' }} /> User FCM Token Registration Roster
            </h3>

            {!fcmStatus?.users_detail || fcmStatus.users_detail.length === 0 ? (
              <div style={{ padding: '30px', textAlign: 'center', color: 'var(--text-muted)' }}>
                {loadingStatus ? 'Fetching live FCM status...' : 'No users found.'}
              </div>
            ) : (
              <table className="data-table" style={{ width: '100%' }}>
                <thead>
                  <tr>
                    <th>User Name</th>
                    <th>Role</th>
                    <th>FCM Token Status</th>
                    <th>Push Delivery Ready</th>
                  </tr>
                </thead>
                <tbody>
                  {fcmStatus.users_detail.map(u => (
                    <tr key={u.id}>
                      <td style={{ fontWeight: 700, color: 'var(--text-dark)' }}>{u.name}</td>
                      <td>
                        <span className="badge badge-neutral" style={{ textTransform: 'uppercase', fontSize: '10px' }}>
                          {u.role}
                        </span>
                      </td>
                      <td>
                        {u.has_fcm_token ? (
                          <span className="badge badge-success" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                            <CheckCircle2 size={12} /> Active FCM Token Registered
                          </span>
                        ) : (
                          <span className="badge badge-warning" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                            <Info size={12} /> No Token (Pending Login)
                          </span>
                        )}
                      </td>
                      <td>
                        {u.has_fcm_token ? (
                          <span style={{ fontSize: '12px', color: '#16a34a', fontWeight: 700 }}>Ready for Push</span>
                        ) : (
                          <span style={{ fontSize: '12px', color: '#94a3b8' }}>In-App WebSocket Only</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
