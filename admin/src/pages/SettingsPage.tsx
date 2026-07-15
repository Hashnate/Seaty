import { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getPlatformSettings, updatePlatformSetting } from '../api/client';
import { Settings, Save, RefreshCw } from 'lucide-react';

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

      {/* Commission & Charges */}
      <div className="table-card" style={{ maxWidth: '700px' }}>
        <h3 className="table-title" style={{ marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Settings size={18} style={{ color: '#e65100' }} /> Platform Settings
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
              const meta = SETTING_LABELS[s.key] || { label: s.key, type: 'text' };
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
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <div style={{ position: 'relative' }}>
                      <input
                        type={meta.type}
                        className="form-input"
                        style={{ width: '140px', textAlign: 'right', paddingRight: meta.unit ? '40px' : '12px' }}
                        value={editValues[s.key] || ''}
                        onChange={e => setEditValues({ ...editValues, [s.key]: e.target.value })}
                      />
                      {meta.unit && (
                        <span style={{
                          position: 'absolute', right: '12px', top: '50%', transform: 'translateY(-50%)',
                          fontSize: '12px', color: '#9ca3af', fontWeight: 600
                        }}>{meta.unit}</span>
                      )}
                    </div>
                    <button
                      onClick={() => handleSave(s.key)}
                      disabled={!hasChanged || saving === s.key}
                      style={{
                        padding: '8px 12px', border: 'none', borderRadius: '8px',
                        background: hasChanged ? '#e65100' : '#e2e8f0',
                        color: hasChanged ? 'white' : '#94a3b8',
                        cursor: hasChanged ? 'pointer' : 'default',
                        display: 'flex', alignItems: 'center', gap: '4px',
                        fontSize: '12px', fontWeight: 600,
                        transition: 'all 0.2s ease',
                      }}
                    >
                      <Save size={14} /> {saving === s.key ? '...' : 'Save'}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Server Status */}
      <div className="table-card" style={{ maxWidth: '700px', marginTop: '20px' }}>
        <h3 className="table-title" style={{ marginBottom: '20px' }}>Server Status</h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {[
            { name: 'FastAPI Backend', url: `${window.location.protocol}//${window.location.host}/api/v1` },
            { name: 'WebSockets GPS Hub', url: `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/api/v1/ws` },
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
  );
}
