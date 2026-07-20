import React from 'react';
import { useNavigate, useLocation, Link } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import NotificationDrawer from './NotificationDrawer';
import {
  Activity,
  CheckCircle,
  Building2,
  Users,
  Map as MapIcon,
  Settings as SettingsIcon,
  Route as RouteIcon,
  LogOut,
  Bus,
  Calendar,
  Contact,
  ChevronDown,
  Key,
  ChevronRight,
} from 'lucide-react';

const NAV_ITEMS = [
  { path: '/', icon: Activity, label: 'Overview & Stats' },
  { path: '/approvals', icon: CheckCircle, label: 'Pending Approvals' },
  { path: '/companies', icon: Building2, label: 'Bus Companies' },
  { path: '/routes', icon: RouteIcon, label: 'Route Templates' },
  { path: '/fleet', icon: Bus, label: 'My Fleet' },
  { path: '/trips', icon: Calendar, label: 'Trip Scheduling' },
  { path: '/conductors', icon: Contact, label: 'My Conductors' },
  { path: '/map', icon: MapIcon, label: 'Live Fleet Map', badge: 'Live' },
  { path: '/bookings', icon: Users, label: 'Bookings Log' },
  { path: '/settings', icon: SettingsIcon, label: 'Console Settings' },
];

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const location = useLocation();
  const { logout, user, token } = useAuth();

  const [isProfileOpen, setIsProfileOpen] = React.useState(false);
  const profileMenuRef = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (profileMenuRef.current && !profileMenuRef.current.contains(event.target as Node)) {
        setIsProfileOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);
  const [isPasswordModalOpen, setIsPasswordModalOpen] = React.useState(false);
  const [currentPassword, setCurrentPassword] = React.useState('');
  const [newPassword, setNewPassword] = React.useState('');
  const [confirmPassword, setConfirmPassword] = React.useState('');
  const [isSubmittingPassword, setIsSubmittingPassword] = React.useState(false);
  const [passwordError, setPasswordError] = React.useState<string | null>(null);
  const [passwordSuccess, setPasswordSuccess] = React.useState<string | null>(null);

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordError(null);
    setPasswordSuccess(null);

    if (newPassword.length < 6) {
      setPasswordError('New password must be at least 6 characters long.');
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordError('New passwords do not match.');
      return;
    }

    setIsSubmittingPassword(true);
    try {
      const { changePassword } = await import('../api/client');
      if (!token) throw new Error('Not authenticated.');
      await changePassword(token, {
        current_password: currentPassword,
        new_password: newPassword
      });
      setPasswordSuccess('Password updated successfully!');
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      setTimeout(() => {
        setIsPasswordModalOpen(false);
        setPasswordSuccess(null);
      }, 1500);
    } catch (err) {
      setPasswordError(err instanceof Error ? err.message : 'Failed to change password.');
    } finally {
      setIsSubmittingPassword(false);
    }
  };

  const typedUser = user as { full_name?: string; email?: string; role?: string } | null;
  const userRole = typedUser?.role || 'admin';

  const visibleNavItems = NAV_ITEMS.filter(item => {
    if (userRole === 'owner') {
      return ['/', '/fleet', '/trips', '/conductors', '/bookings', '/map'].includes(item.path);
    }
    // Admins can see all views
    return ['/', '/approvals', '/companies', '/routes', '/fleet', '/trips', '/conductors', '/map', '/bookings', '/settings'].includes(item.path);
  });

  return (
    <div className="dashboard-layout">
      <aside className="sidebar">
        <Link 
          to="/"
          className="sidebar-brand" 
          style={{ 
            display: 'flex', 
            justifyContent: 'center', 
            alignItems: 'center', 
            padding: '0', 
            margin: '0 0 20px 0', 
            cursor: 'pointer',
            width: '100%',
            textDecoration: 'none'
          }}
        >
          <img src="/app_logo.png" alt="Seaty Logo" style={{ height: '120px', maxWidth: '100%', objectFit: 'contain' }} />
        </Link>
        <ul className="sidebar-menu">
          {visibleNavItems.map(item => {
            const isActive = location.pathname === item.path;
            return (
              <li
                key={item.path}
                className={`sidebar-item ${isActive ? 'active' : ''}`}
                onClick={() => navigate(item.path)}
              >
                <item.icon size={18} />
                {item.label}
                {item.badge && (
                  <span className="badge badge-success" style={{ marginLeft: 'auto', padding: '2px 6px', fontSize: '10px' }}>
                    {item.badge}
                  </span>
                )}
              </li>
            );
          })}
        </ul>
      </aside>
      <main className="main-content" style={{ display: 'flex', flexDirection: 'column' }}>
        <header className="admin-navbar" style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: '14px 28px',
          background: 'rgba(255, 255, 255, 0.85)',
          backdropFilter: 'blur(20px) saturate(180%)',
          WebkitBackdropFilter: 'blur(20px) saturate(180%)',
          border: '1px solid rgba(255, 255, 255, 0.5)',
          borderRadius: '16px',
          marginBottom: '28px',
          boxShadow: '0 8px 32px 0 rgba(31, 38, 135, 0.04), inset 0 1px 0 rgba(255, 255, 255, 0.6)'
        }}>
          <div className="navbar-left" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span style={{ fontSize: '11px', textTransform: 'uppercase', letterSpacing: '0.06em', fontWeight: 600, color: 'var(--text-muted)' }}>Console Control</span>
            <ChevronRight size={13} style={{ color: 'var(--text-muted)', opacity: 0.4 }} />
            <span style={{ fontSize: '14px', fontWeight: 700, color: 'var(--color-primary)' }}>
              {location.pathname === '/' ? 'Dashboard Overview' : visibleNavItems.find(item => item.path === location.pathname)?.label || 'Console'}
            </span>
          </div>

          <div className="navbar-right" style={{ display: 'flex', alignItems: 'center', gap: '16px', marginRight: '4px' }}>
            <NotificationDrawer />
            <div ref={profileMenuRef} className="profile-menu-container" style={{ position: 'relative' }}>
              <button 
                onClick={() => setIsProfileOpen(!isProfileOpen)} 
                className="profile-btn" 
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '10px', 
                  background: 'var(--bg-secondary)', 
                  border: '1px solid var(--border-color)', 
                  cursor: 'pointer',
                  color: 'var(--text-dark)',
                  padding: '6px 14px 6px 6px',
                  borderRadius: '30px',
                  boxShadow: '0 2px 6px rgba(0, 0, 0, 0.02)',
                  transition: 'all 0.2s ease',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.borderColor = 'rgba(37, 99, 235, 0.3)';
                  e.currentTarget.style.boxShadow = '0 4px 12px rgba(37, 99, 235, 0.05)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.borderColor = 'var(--border-color)';
                  e.currentTarget.style.boxShadow = '0 2px 6px rgba(0, 0, 0, 0.02)';
                }}
              >
                <div style={{
                  width: '32px',
                  height: '32px',
                  borderRadius: '50%',
                  background: 'linear-gradient(135deg, var(--color-primary-hover), var(--color-primary))',
                  color: 'white',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: '14px',
                  boxShadow: '0 2px 8px rgba(37, 99, 235, 0.2)',
                  border: '1.5px solid white'
                }}>
                  {typedUser?.full_name ? String(typedUser.full_name).charAt(0).toUpperCase() : 'A'}
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', textAlign: 'left', minWidth: '85px' }}>
                  <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-dark)' }}>{typedUser?.full_name || 'Admin User'}</span>
                  <span style={{ fontSize: '9px', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em', marginTop: '1px' }}>{String(typedUser?.role || 'admin')}</span>
                </div>
                <ChevronDown size={14} style={{ opacity: 0.5, marginLeft: '4px' }} />
              </button>

              {isProfileOpen && (
                  <div className="profile-dropdown" style={{
                    position: 'absolute',
                    right: 0,
                    top: '100%',
                    marginTop: '8px',
                    width: '240px',
                    background: 'rgba(255, 255, 255, 0.95)',
                    backdropFilter: 'blur(20px) saturate(180%)',
                    WebkitBackdropFilter: 'blur(20px) saturate(180%)',
                    border: '1px solid rgba(10, 37, 64, 0.08)',
                    borderRadius: '14px',
                    boxShadow: '0 10px 30px rgba(10, 37, 64, 0.08)',
                    zIndex: 999,
                    padding: '6px',
                    overflow: 'hidden'
                  }}>
                    <div style={{ padding: '12px 12px 10px 12px', borderBottom: '1px solid rgba(10, 37, 64, 0.04)' }}>
                      <strong style={{ display: 'block', fontSize: '13.5px', color: 'var(--text-dark)' }}>{typedUser?.full_name}</strong>
                      <span style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', wordBreak: 'break-all', marginTop: '2px' }}>{typedUser?.email}</span>
                      <span style={{ 
                        display: 'inline-block', 
                        fontSize: '9px', 
                        fontWeight: 700, 
                        background: 'rgba(37, 99, 235, 0.08)', 
                        color: 'var(--color-primary)',
                        padding: '2px 8px',
                        border: '1px solid rgba(37, 99, 235, 0.15)',
                        borderRadius: '12px',
                        marginTop: '6px',
                        textTransform: 'uppercase',
                        letterSpacing: '0.04em'
                      }}>{typedUser?.role}</span>
                    </div>
                    <ul style={{ listStyle: 'none', padding: '4px 0 0 0', margin: 0 }}>
                      <li 
                        onClick={() => {
                          setIsProfileOpen(false);
                          setIsPasswordModalOpen(true);
                        }}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: '10px',
                          padding: '10px 12px',
                          margin: '2px 4px',
                          borderRadius: '8px',
                          fontSize: '13px',
                          fontWeight: 500,
                          color: 'var(--text-dark)',
                          cursor: 'pointer',
                          transition: 'all 0.15s ease',
                        }}
                        onMouseEnter={(e) => {
                          e.currentTarget.style.backgroundColor = 'rgba(37, 99, 235, 0.05)';
                          e.currentTarget.style.color = 'var(--color-primary)';
                        }}
                        onMouseLeave={(e) => {
                          e.currentTarget.style.backgroundColor = 'transparent';
                          e.currentTarget.style.color = 'var(--text-dark)';
                        }}
                      >
                        <Key size={15} style={{ color: 'var(--color-primary)' }} />
                        Change Password
                      </li>
                      <li 
                        onClick={handleLogout}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: '10px',
                          padding: '10px 12px',
                          margin: '2px 4px',
                          borderRadius: '8px',
                          fontSize: '13px',
                          fontWeight: 500,
                          color: '#ef4444',
                          cursor: 'pointer',
                          borderTop: '1px solid rgba(10, 37, 64, 0.03)',
                          transition: 'all 0.15s ease',
                        }}
                        onMouseEnter={(e) => {
                          e.currentTarget.style.backgroundColor = 'rgba(239, 68, 68, 0.05)';
                          e.currentTarget.style.color = '#dc2626';
                        }}
                        onMouseLeave={(e) => {
                          e.currentTarget.style.backgroundColor = 'transparent';
                          e.currentTarget.style.color = '#ef4444';
                        }}
                      >
                        <LogOut size={15} />
                        Sign Out
                      </li>
                    </ul>
                  </div>
              )}
            </div>
          </div>
        </header>
        <div style={{ flexGrow: 1 }}>
          {children}
        </div>
      </main>

      {isPasswordModalOpen && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(0, 0, 0, 0.4)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 10000,
          backdropFilter: 'blur(2px)'
        }}>
          <div style={{
            background: 'var(--bg-card, #ffffff)',
            width: '400px',
            borderRadius: '16px',
            boxShadow: '0 10px 25px rgba(0,0,0,0.15)',
            border: '1px solid var(--border-color)',
            overflow: 'hidden'
          }}>
            <div style={{
              padding: '16px 20px',
              borderBottom: '1px solid var(--border-color)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center'
            }}>
              <h3 style={{ margin: 0, fontSize: '16px', fontWeight: 600 }}>Change Password</h3>
              <button 
                onClick={() => {
                  setIsPasswordModalOpen(false);
                  setPasswordError(null);
                  setPasswordSuccess(null);
                  setCurrentPassword('');
                  setNewPassword('');
                  setConfirmPassword('');
                }}
                style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '18px', opacity: 0.5 }}
              >
                &times;
              </button>
            </div>
            <form onSubmit={handleChangePassword} style={{ padding: '20px' }}>
              {passwordError && (
                <div style={{
                  background: '#fef2f2',
                  border: '1px solid #fca5a5',
                  color: '#b91c1c',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  fontSize: '12px',
                  marginBottom: '16px'
                }}>
                  {passwordError}
                </div>
              )}
              {passwordSuccess && (
                <div style={{
                  background: '#f0fdf4',
                  border: '1px solid #86efac',
                  color: '#15803d',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  fontSize: '12px',
                  marginBottom: '16px'
                }}>
                  {passwordSuccess}
                </div>
              )}
              <div style={{ marginBottom: '14px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '6px', color: 'var(--text-dark)' }}>
                  Current Password
                </label>
                <input
                  type="password"
                  className="form-input"
                  style={{ width: '100%' }}
                  value={currentPassword}
                  onChange={(e) => setCurrentPassword(e.target.value)}
                  required
                />
              </div>
              <div style={{ marginBottom: '14px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '6px', color: 'var(--text-dark)' }}>
                  New Password
                </label>
                <input
                  type="password"
                  className="form-input"
                  style={{ width: '100%' }}
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  required
                />
              </div>
              <div style={{ marginBottom: '20px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '6px', color: 'var(--text-dark)' }}>
                  Confirm New Password
                </label>
                <input
                  type="password"
                  className="form-input"
                  style={{ width: '100%' }}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  required
                />
              </div>
              <div style={{ display: 'flex', gap: '10px', justifyContent: 'flex-end' }}>
                <button
                  type="button"
                  onClick={() => {
                    setIsPasswordModalOpen(false);
                    setPasswordError(null);
                    setPasswordSuccess(null);
                    setCurrentPassword('');
                    setNewPassword('');
                    setConfirmPassword('');
                  }}
                  style={{
                    padding: '8px 16px',
                    background: 'none',
                    border: '1px solid var(--border-color)',
                    borderRadius: '8px',
                    cursor: 'pointer',
                    fontSize: '13px',
                    fontWeight: 600,
                  }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmittingPassword}
                  style={{
                    padding: '8px 16px',
                    background: 'var(--color-primary, #2563eb)',
                    color: 'white',
                    border: 'none',
                    borderRadius: '8px',
                    cursor: 'pointer',
                    fontSize: '13px',
                    fontWeight: 600,
                  }}
                >
                  {isSubmittingPassword ? 'Saving...' : 'Update Password'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
