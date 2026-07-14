import React from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
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
} from 'lucide-react';

const NAV_ITEMS = [
  { path: '/', icon: Activity, label: 'Overview & Stats' },
  { path: '/approvals', icon: CheckCircle, label: 'Pending Approvals' },
  { path: '/companies', icon: Building2, label: 'Bus Companies' },
  { path: '/routes', icon: RouteIcon, label: 'Route Templates' },
  { path: '/fleet', icon: Bus, label: 'My Fleet' },
  { path: '/trips', icon: Calendar, label: 'Trip Scheduling' },
  { path: '/contractors', icon: Contact, label: 'My Contractors' },
  { path: '/map', icon: MapIcon, label: 'Live Fleet Map', badge: 'Live' },
  { path: '/bookings', icon: Users, label: 'Bookings Log' },
  { path: '/settings', icon: SettingsIcon, label: 'Console Settings' },
];

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const location = useLocation();
  const { logout, user } = useAuth();

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const userName = (user as { full_name?: string })?.full_name || 'Sys Admin';
  const userRole = (user as { role?: string })?.role || 'admin';

  const visibleNavItems = NAV_ITEMS.filter(item => {
    if (userRole === 'owner') {
      return ['/', '/fleet', '/trips', '/contractors', '/bookings', '/map'].includes(item.path);
    }
    return ['/', '/approvals', '/companies', '/routes', '/map', '/bookings', '/settings'].includes(item.path);
  });

  return (
    <div className="dashboard-layout">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <img src="/app_logo.png" alt="Seaty Logo" style={{ height: '28px', objectFit: 'contain' }} />
        </div>
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
        <div className="sidebar-footer">
          <div className="user-profile-badge" style={{ marginBottom: '20px' }}>
            <div className="user-avatar">{userName.substring(0, 2).toUpperCase()}</div>
            <div className="user-info">
              <span className="user-name">{userName}</span>
              <span className="user-role">{userRole}</span>
            </div>
          </div>
          <div className="sidebar-item" onClick={handleLogout} style={{ color: '#ef4444' }}>
            <LogOut size={18} />
            Sign Out
          </div>
        </div>
      </aside>
      <main className="main-content">
        {children}
      </main>
    </div>
  );
}
