import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getPlatformSettings, updatePlatformSetting, broadcastNotification } from '../api/client';
import { Settings, Save, RefreshCw, Megaphone, Send } from 'lucide-react';
import CustomSelect from '../components/CustomSelect';

const AUDIENCE_OPTIONS = [
  { value: 'passenger', label: 'Passengers Only' },
  { value: 'conductor', label: 'Conductors Only' },
  { value: 'owner', label: 'Bus Owners Only' },
  { value: 'admin', label: 'Admins Only' },
  { value: 'all', label: 'All Users (Global Broadcast)' }
];

interface PlatformSetting {
  id: string;
  key: string;
  value: string;
  description: string | null;
  updated_at: string;
}

const SETTING_LABELS: Record<string, { label: string; type: 'text' | 'number'; unit?: string }> = {
  commission_percentage: { label: 'Commission Percentage', type: 'number', unit: '%' },
  commission_fixed_fee: { label: 'Fixed Booking Fee', type: 'number', unit: 'LKR' },
  seat_hold_duration_minutes: { label: 'Seat Hold Duration', type: 'number', unit: 'minutes' },
  payment_gateway: { label: 'Payment Gateway', type: 'text' },
  currency: { label: 'Default Currency', type: 'text' },
};

export default function SettingsPage() {
  const { token } = useAuth();
  const [settings, setSettings] = useState<PlatformSetting[]>([]);
  const [editValues, setEditValues] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [focusedKey, setFocusedKey] = useState<string | null>(null);

  const [broadcastTitle, setBroadcastTitle] = useState('');
  const [broadcastMessage, setBroadcastMessage] = useState('');
  const [targetRole, setTargetRole] = useState('passenger');
  const [sendingBroadcast, setSendingBroadcast] = useState(false);
  const [broadcastSuccess, setBroadcastSuccess] = useState<string | null>(null);
  const [broadcastError, setBroadcastError] = useState<string | null>(null);

  const handleBroadcastSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !broadcastTitle.trim() || !broadcastMessage.trim()) return;

    setSendingBroadcast(true);
    setBroadcastSuccess(null);
    setBroadcastError(null);

    try {
      const response = await broadcastNotification(token, broadcastTitle, broadcastMessage, targetRole) as { message: string };
      setBroadcastSuccess(response.message || 'Broadcast successfully sent to target audience!');
      setBroadcastTitle('');
      setBroadcastMessage('');
    } catch (err) {
      setBroadcastError(err instanceof Error ? err.message : 'Failed to send broadcast');
    } finally {
      setSendingBroadcast(false);
    }
  };

  const fetchSettings = async () => {

    if (!token) return;
    setLoading(true);
    try {
      const data = await getPlatformSettings(token) as PlatformSetting[];
      setSettings(data);
      const values: Record<string, string> = {};
      data.forEach(s => { values[s.key] = s.value; });
      setEditValues(values);
    } catch {
      setSettings([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchSettings(); }, [token]);

  const handleSave = async (key: string) => {
    if (!token) return;
    setSaving(key);
    try {
      await updatePlatformSetting(token, key, editValues[key]);
      await fetchSettings();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to update setting');
    } finally {
      setSaving(null);
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Console Configuration</h1>
          <p className="page-subtitle">Configure booking charges, commission rates, payment gateways, and platform parameters.</p>
        </div>
        <button onClick={fetchSettings} className="btn-action btn-action-success" style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
          <RefreshCw size={14} /> Refresh
        </button>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(450px, 1fr))',
        gap: '24px',
        alignItems: 'start',
        marginTop: '20px'
      }}>
        {/* Left Column */}
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          {/* Commission & Charges */}
          <div className="table-card" style={{ margin: 0 }}>
            <h3 className="table-title" style={{ marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Settings size={18} style={{ color: '#2563eb' }} /> Platform Settings
            </h3>
            {loading ? (
              <div style={{ textAlign: 'center', padding: '30px', color: '#9ca3af' }}>Loading settings...</div>
            ) : settings.length === 0 ? (
              <div style={{ textAlign: 'center', padding: '30px', color: '#9ca3af' }}>
                No settings found. Make sure the backend has seed data.
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                {settings.map(s => {
                  const meta = SETTING_LABELS[s.key] || { label: s.key, type: 'text' as const, unit: undefined };
                  const hasChanged = editValues[s.key] !== s.value;
                  return (
                    <div key={s.id} style={{
                      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                      borderBottom: '1px solid var(--border-color)', paddingBottom: '14px',
                    }}>
                      <div style={{ flex: 1 }}>
                        <strong style={{ fontSize: '14px' }}>{meta.label}</strong>
                        {s.description && (
                          <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>{s.description}</div>
                        )}
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                        <div style={{ 
                          display: 'flex', 
                          alignItems: 'center', 
                          border: focusedKey === s.key ? '1px solid var(--color-primary)' : '1px solid var(--border-color)', 
                          borderRadius: '8px', 
                          overflow: 'hidden', 
                          width: '170px',
                          minWidth: '170px',
                          maxWidth: '170px',
                          flexShrink: 0,
                          background: '#ffffff',
                          boxShadow: focusedKey === s.key ? '0 0 0 3px rgba(37, 99, 235, 0.15)' : 'none',
                          transition: 'all 0.15s ease',
                        }}>
                          <input
                            type={meta.type}
                            style={{ 
                              width: '100%', 
                              minWidth: 0,
                              flex: 1,
                              border: 'none', 
                              outline: 'none',
                              padding: '10px 12px', 
                              background: 'transparent',
                              textAlign: meta.unit ? 'right' : 'left',
                              fontSize: '13px',
                              fontWeight: 600,
                              color: 'var(--text-dark)'
                            }}
                            value={editValues[s.key] || ''}
                            onChange={e => setEditValues({ ...editValues, [s.key]: e.target.value })}
                            onFocus={() => setFocusedKey(s.key)}
                            onBlur={() => setFocusedKey(null)}
                          />
                          {meta.unit && (
                            <span style={{
                              padding: '10px 12px',
                              background: 'var(--bg-secondary)',
                              borderLeft: '1px solid var(--border-color)',
                              fontSize: '11px',
                              color: 'var(--text-muted)',
                              fontWeight: 700,
                              whiteSpace: 'nowrap',
                              flexShrink: 0,
                              minWidth: '60px',
                              textAlign: 'center'
                            }}>{meta.unit}</span>
                          )}
                        </div>
                        <button
                          onClick={() => handleSave(s.key)}
                          disabled={!hasChanged || saving === s.key}
                          style={{
                            height: '38px',
                            padding: '0 16px',
                            borderRadius: '8px',
                            background: hasChanged ? 'var(--color-primary)' : 'var(--bg-secondary)',
                            border: hasChanged ? 'none' : '1px solid var(--border-color)',
                            color: hasChanged ? 'white' : 'var(--text-muted)',
                            cursor: hasChanged ? 'pointer' : 'not-allowed',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            gap: '6px',
                            fontSize: '12.5px',
                            fontWeight: 600,
                            transition: 'all 0.2s ease',
                          }}
                        >
                          <Save size={14} /> {saving === s.key ? 'Saving' : 'Save'}
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        {/* Right Column */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          {/* Broadcast Push Notification */}
          <div className="table-card" style={{ margin: 0 }}>
            <h3 className="table-title" style={{ marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Megaphone size={18} style={{ color: '#2563eb' }} /> Broadcast Notification
            </h3>
            <p className="page-subtitle" style={{ marginBottom: '20px' }}>
              Send a push notification broadcast directly to all passengers, conductors, owners, or everyone registered on the Seaty platform.
            </p>

            {broadcastSuccess && (
              <div className="badge badge-success" style={{ width: '100%', marginBottom: '16px', padding: '10px 14px', borderRadius: '8px', display: 'flex', justifyContent: 'center' }}>
                {broadcastSuccess}
              </div>
            )}
            {broadcastError && (
              <div className="badge badge-danger" style={{ width: '100%', marginBottom: '16px', padding: '10px 14px', borderRadius: '8px', display: 'flex', justifyContent: 'center' }}>
                {broadcastError}
              </div>
            )}

            <form onSubmit={handleBroadcastSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Target Audience</label>
                <CustomSelect
                  options={AUDIENCE_OPTIONS}
                  value={targetRole}
                  onChange={val => setTargetRole(val)}
                  style={{ width: '100%' }}
                />
              </div>

              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Notification Title</label>
                <input
                  type="text"
                  className="form-input"
                  placeholder="e.g. Welcome to Seaty"
                  value={broadcastTitle}
                  onChange={e => setBroadcastTitle(e.target.value)}
                  required
                />
              </div>

              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Notification Message</label>
                <textarea
                  className="form-input"
                  placeholder="Enter details of your message..."
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
                  padding: '12px',
                  border: 'none',
                  borderRadius: '8px',
                  background: (broadcastTitle.trim() && broadcastMessage.trim() && !sendingBroadcast) ? '#2563eb' : '#e2e8f0',
                  color: (broadcastTitle.trim() && broadcastMessage.trim() && !sendingBroadcast) ? 'white' : '#94a3b8',
                  cursor: (broadcastTitle.trim() && broadcastMessage.trim() && !sendingBroadcast) ? 'pointer' : 'default',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '8px',
                  fontSize: '14px',
                  fontWeight: 600,
                  transition: 'all 0.2s ease',
                  marginTop: '8px'
                }}
              >
                <Send size={16} /> {sendingBroadcast ? 'Broadcasting...' : 'Send Broadcast'}
              </button>
            </form>
          </div>

          {/* Server Status */}
          <div className="table-card" style={{ margin: 0 }}>
            <h3 className="table-title" style={{ marginBottom: '20px' }}>Server Status</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {[
                { name: 'FastAPI Backend', url: 'https://api.seaty.hashnate.com/api/v1' },
                { name: 'WebSockets GPS Hub', url: 'wss://api.seaty.hashnate.com/api/v1/ws' },
                { name: 'PostgreSQL Database', url: 'Docker Postgres Pool' },
              ].map((srv, idx) => (
                <div key={idx} style={{
                  display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                  borderBottom: idx < 2 ? '1px solid var(--border-color)' : 'none', paddingBottom: '12px'
                }}>
                  <div>
                    <strong>{srv.name}</strong>
                    <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>Connection: {srv.url}</div>
                  </div>
                  <span className="badge badge-success">Online</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
