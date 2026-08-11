import React, { useState, useEffect, useRef } from 'react';
import { useAuth } from '../hooks/useAuth';
import {
  getBanners,
  createBanner,
  updateBanner,
  deleteBanner,
  uploadBannerImage,
  type HeroBanner,
} from '../api/client';
import { Image as ImageIcon, Plus, Trash2, Eye, EyeOff, ArrowUp, ArrowDown, UploadCloud } from 'lucide-react';

export default function BannersPage() {
  const { token } = useAuth();
  const [banners, setBanners] = useState<HeroBanner[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState('');

  const [showModal, setShowModal] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [newImageUrl, setNewImageUrl] = useState('');
  const [newTitle, setNewTitle] = useState('');
  const [newSubtitle, setNewSubtitle] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  const fetchBanners = async () => {
    if (!token) return;
    setLoading(true);
    try {
      const data = await getBanners(token);
      setBanners(data);
      setError('');
    } catch (e) {
      setBanners([]);
      setError(e instanceof Error ? e.message : 'Failed to load banners');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBanners();
  }, [token]);

  const handleFilePicked = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !token) return;
    setUploading(true);
    setError('');
    try {
      const res = await uploadBannerImage(token, file);
      setNewImageUrl(res.url);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Image upload failed');
    } finally {
      setUploading(false);
      // Allow re-picking the same file after a failure
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !newImageUrl) return;
    try {
      await createBanner(token, {
        image_url: newImageUrl,
        title: newTitle.trim() || null,
        subtitle: newSubtitle.trim() || null,
        // Append to the end of the carousel by default.
        sort_order: banners.length,
        is_active: true,
      });
      setShowModal(false);
      setNewImageUrl('');
      setNewTitle('');
      setNewSubtitle('');
      fetchBanners();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create banner');
    }
  };

  const handleToggleActive = async (banner: HeroBanner) => {
    if (!token) return;
    setBusyId(banner.id);
    try {
      await updateBanner(token, banner.id, { is_active: !banner.is_active });
      fetchBanners();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update banner');
    } finally {
      setBusyId(null);
    }
  };

  /** Swaps sort_order with the neighbour so the carousel order is explicit. */
  const handleMove = async (index: number, direction: -1 | 1) => {
    if (!token) return;
    const target = index + direction;
    if (target < 0 || target >= banners.length) return;

    const a = banners[index];
    const b = banners[target];
    setBusyId(a.id);
    try {
      await updateBanner(token, a.id, { sort_order: target });
      await updateBanner(token, b.id, { sort_order: index });
      fetchBanners();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to reorder banners');
    } finally {
      setBusyId(null);
    }
  };

  const handleDelete = async (banner: HeroBanner) => {
    if (!token) return;
    if (!window.confirm('Remove this banner from the app home screen?')) return;
    setBusyId(banner.id);
    try {
      await deleteBanner(token, banner.id);
      fetchBanners();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete banner');
    } finally {
      setBusyId(null);
    }
  };

  const activeCount = banners.filter(b => b.is_active).length;

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Home Screen Banners</h1>
          <p className="page-subtitle">
            Images shown in the passenger app's home carousel. Changes appear in the app
            without a new release. {activeCount === 0 && banners.length > 0
              ? 'No banners are visible right now, so the app falls back to its built-in images.'
              : ''}
          </p>
        </div>
        <button
          className="btn-primary"
          style={{ width: 'auto', padding: '10px 20px', display: 'flex', alignItems: 'center', gap: '8px' }}
          onClick={() => { setError(''); setShowModal(true); }}
        >
          <Plus size={16} /> Add Banner
        </button>
      </div>

      {error && (
        <div style={{
          background: 'rgba(220, 38, 38, 0.06)',
          border: '1px solid rgba(220, 38, 38, 0.2)',
          color: '#b91c1c',
          padding: '10px 14px',
          borderRadius: '8px',
          fontSize: '13px',
          marginBottom: '16px',
        }}>
          {error}
        </div>
      )}

      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading banners...</div>
        ) : banners.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>
            <ImageIcon size={48} style={{ color: '#9ca3af', marginBottom: '16px' }} />
            <h4>No banners configured</h4>
            <p style={{ fontSize: '13px', marginTop: '4px' }}>
              The app is currently showing its built-in images. Add a banner to override them.
            </p>
          </div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th style={{ width: '140px' }}>Preview</th>
                <th>Caption</th>
                <th style={{ width: '110px' }}>Order</th>
                <th style={{ width: '110px' }}>Visibility</th>
                <th style={{ width: '90px' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {banners.map((b, index) => (
                <tr key={b.id} style={{ opacity: b.is_active ? 1 : 0.55 }}>
                  <td>
                    <img
                      src={b.image_url}
                      alt={b.title || 'Banner'}
                      style={{
                        width: '120px',
                        height: '64px',
                        objectFit: 'cover',
                        borderRadius: '8px',
                        border: '1px solid rgba(0,0,0,0.08)',
                        background: '#f1f5f9',
                        display: 'block',
                      }}
                    />
                  </td>
                  <td>
                    <strong>{b.title || <span style={{ color: '#9ca3af', fontStyle: 'italic' }}>No title</span>}</strong>
                    {b.subtitle && (
                      <div style={{ fontSize: '12px', color: 'var(--text-muted, #6b7280)', marginTop: '2px' }}>
                        {b.subtitle}
                      </div>
                    )}
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <button
                        onClick={() => handleMove(index, -1)}
                        disabled={index === 0 || busyId === b.id}
                        title="Move up"
                        style={iconBtnStyle(index === 0 || busyId === b.id)}
                      >
                        <ArrowUp size={14} />
                      </button>
                      <button
                        onClick={() => handleMove(index, 1)}
                        disabled={index === banners.length - 1 || busyId === b.id}
                        title="Move down"
                        style={iconBtnStyle(index === banners.length - 1 || busyId === b.id)}
                      >
                        <ArrowDown size={14} />
                      </button>
                      <span style={{ fontSize: '12px', color: '#9ca3af', marginLeft: '4px' }}>#{index + 1}</span>
                    </div>
                  </td>
                  <td>
                    <button
                      onClick={() => handleToggleActive(b)}
                      disabled={busyId === b.id}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '6px',
                        padding: '4px 10px',
                        borderRadius: '20px',
                        fontSize: '11px',
                        fontWeight: 600,
                        cursor: busyId === b.id ? 'default' : 'pointer',
                        border: '1px solid',
                        borderColor: b.is_active ? 'rgba(16, 185, 129, 0.25)' : 'rgba(107, 114, 128, 0.25)',
                        background: b.is_active ? 'rgba(16, 185, 129, 0.08)' : 'rgba(107, 114, 128, 0.08)',
                        color: b.is_active ? '#047857' : '#4b5563',
                      }}
                    >
                      {b.is_active ? <Eye size={12} /> : <EyeOff size={12} />}
                      {b.is_active ? 'Visible' : 'Hidden'}
                    </button>
                  </td>
                  <td>
                    <button
                      onClick={() => handleDelete(b)}
                      disabled={busyId === b.id}
                      title="Delete banner"
                      style={{
                        ...iconBtnStyle(busyId === b.id),
                        color: '#b91c1c',
                        borderColor: 'rgba(220, 38, 38, 0.2)',
                      }}
                    >
                      <Trash2 size={14} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showModal && (
        <div
          style={{
            position: 'fixed',
            inset: 0,
            background: 'rgba(15, 23, 42, 0.45)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000,
            padding: '20px',
          }}
          onClick={() => setShowModal(false)}
        >
          <div
            style={{
              background: '#fff',
              borderRadius: '16px',
              padding: '24px',
              width: '100%',
              maxWidth: '460px',
              boxShadow: '0 20px 40px rgba(0,0,0,0.2)',
            }}
            onClick={e => e.stopPropagation()}
          >
            <h3 style={{ marginBottom: '4px' }}>Add Home Screen Banner</h3>
            <p style={{ fontSize: '13px', color: '#6b7280', marginBottom: '18px' }}>
              Landscape images work best. Max 5MB — JPEG, PNG or WebP.
            </p>

            <form onSubmit={handleCreate}>
              <div
                onClick={() => fileInputRef.current?.click()}
                style={{
                  border: '2px dashed rgba(37, 99, 235, 0.3)',
                  borderRadius: '12px',
                  padding: newImageUrl ? '0' : '28px',
                  textAlign: 'center',
                  cursor: 'pointer',
                  marginBottom: '16px',
                  overflow: 'hidden',
                  background: 'rgba(37, 99, 235, 0.03)',
                }}
              >
                {newImageUrl ? (
                  <img
                    src={newImageUrl}
                    alt="Banner preview"
                    style={{ width: '100%', height: '160px', objectFit: 'cover', display: 'block' }}
                  />
                ) : (
                  <div style={{ color: '#2563eb' }}>
                    <UploadCloud size={30} style={{ marginBottom: '8px' }} />
                    <div style={{ fontSize: '13px', fontWeight: 600 }}>
                      {uploading ? 'Uploading...' : 'Click to choose an image'}
                    </div>
                  </div>
                )}
              </div>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                onChange={handleFilePicked}
                style={{ display: 'none' }}
              />

              <label style={labelStyle}>Title (optional)</label>
              <input
                className="form-input"
                value={newTitle}
                onChange={e => setNewTitle(e.target.value)}
                placeholder="e.g. Scenic Coastal Routes"
                style={inputStyle}
              />

              <label style={labelStyle}>Subtitle (optional)</label>
              <input
                className="form-input"
                value={newSubtitle}
                onChange={e => setNewSubtitle(e.target.value)}
                placeholder="e.g. Luxury VIP travel across Sri Lanka"
                style={inputStyle}
              />

              <div style={{ display: 'flex', gap: '10px', marginTop: '20px' }}>
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  style={{
                    flex: 1,
                    padding: '10px',
                    borderRadius: '8px',
                    border: '1px solid rgba(0,0,0,0.12)',
                    background: '#fff',
                    cursor: 'pointer',
                    fontWeight: 600,
                  }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="btn-primary"
                  disabled={!newImageUrl || uploading}
                  style={{ flex: 1, opacity: !newImageUrl || uploading ? 0.6 : 1 }}
                >
                  Add Banner
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

const iconBtnStyle = (disabled: boolean): React.CSSProperties => ({
  padding: '5px 8px',
  borderRadius: '6px',
  background: 'rgba(0,0,0,0.03)',
  border: '1px solid rgba(0,0,0,0.08)',
  color: 'var(--text-main)',
  cursor: disabled ? 'default' : 'pointer',
  opacity: disabled ? 0.4 : 1,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
});

const labelStyle: React.CSSProperties = {
  display: 'block',
  fontSize: '12px',
  fontWeight: 600,
  marginBottom: '6px',
  color: 'var(--text-main)',
};

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '10px 12px',
  borderRadius: '8px',
  border: '1px solid rgba(0,0,0,0.12)',
  marginBottom: '14px',
  fontSize: '14px',
};
