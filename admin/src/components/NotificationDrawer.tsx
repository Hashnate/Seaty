import { useState, useEffect, useRef } from 'react';
import { Bell, X, CheckCheck, Info, FileCheck, Ticket } from 'lucide-react';
import { useAuth } from '../hooks/useAuth';
import { getNotifications, markNotificationRead, markAllNotificationsRead } from '../api/client';

export default function NotificationDrawer() {
  const { token } = useAuth();
  const [isOpen, setIsOpen] = useState(false);
  const [notifications, setNotifications] = useState<any[]>([]);
  const [toast, setToast] = useState<{ title: string; message: string } | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  // Fetch initial notifications
  const fetchNotis = async () => {
    if (!token) return;
    try {
      const data = await getNotifications(token);
      setNotifications(data as any[]);
    } catch (err) {
      console.error('Error fetching notifications:', err);
    }
  };

  useEffect(() => {
    if (token) {
      fetchNotis();

      // Establish WebSocket connection
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = `${protocol}//${window.location.host}/api/v1/notifications/ws?token=${token}`;
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onmessage = (event) => {
        try {
          const newNoti = JSON.parse(event.data);
          // Prepend new notification
          setNotifications((prev) => [newNoti, ...prev]);

          // Show floating toast
          setToast({ title: newNoti.title, message: newNoti.message });
          setTimeout(() => setToast(null), 4000);
        } catch (err) {
          console.error('Error parsing live notification:', err);
        }
      };

      ws.onclose = () => {
        console.log('Notifications WebSocket closed.');
      };

      return () => {
        if (ws.readyState === WebSocket.CONNECTING) {
          ws.onopen = () => {
            ws.close();
          };
        } else {
          ws.close();
        }
      };
    }
  }, [token]);

  const handleMarkAsRead = async (id: string) => {
    if (!token) return;
    try {
      await markNotificationRead(token, id);
      setNotifications((prev) =>
        prev.map((n) => (n.id === id ? { ...n, is_read: true } : n))
      );
    } catch (err) {
      console.error('Failed to mark read:', err);
    }
  };

  const handleMarkAllRead = async () => {
    if (!token) return;
    try {
      await markAllNotificationsRead(token);
      setNotifications((prev) => prev.map((n) => ({ ...n, is_read: true })));
    } catch (err) {
      console.error('Failed to mark all read:', err);
    }
  };

  const unreadCount = notifications.filter((n) => !n.is_read).length;

  const getIcon = (type: string) => {
    switch (type) {
      case 'booking':
        return <Ticket className="noti-icon booking" size={18} />;
      case 'verification':
        return <FileCheck className="noti-icon verification" size={18} />;
      default:
        return <Info className="noti-icon system" size={18} />;
    }
  };

  return (
    <>
      {/* Bell Icon Button */}
      <div className="notification-bell-container" onClick={() => setIsOpen(!isOpen)}>
        <Bell className="bell-icon" size={20} />
        {unreadCount > 0 && (
          <span className="bell-badge">{unreadCount}</span>
        )}
      </div>

      {/* Floating live toast alerts */}
      {toast && (
        <div className="live-notification-toast animate-slide-in">
          <div className="toast-header">
            <Bell size={14} style={{ color: 'var(--color-primary)' }} />
            <strong className="toast-title">{toast.title}</strong>
            <button className="toast-close" onClick={() => setToast(null)}>
              <X size={14} />
            </button>
          </div>
          <div className="toast-body">{toast.message}</div>
        </div>
      )}

      {/* Slide-out Drawer Panel */}
      {isOpen && (
        <div className="notification-drawer-backdrop" onClick={() => setIsOpen(false)}>
          <aside className="notification-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="drawer-header">
              <h3>Alerts & Notifications</h3>
              <div className="drawer-actions">
                {unreadCount > 0 && (
                  <button className="btn-mark-all" onClick={handleMarkAllRead} title="Mark all as read">
                    <CheckCheck size={16} />
                    Mark all read
                  </button>
                )}
                <button className="btn-close-drawer" onClick={() => setIsOpen(false)}>
                  <X size={18} />
                </button>
              </div>
            </div>

            <div className="drawer-body">
              {notifications.length === 0 ? (
                <div className="drawer-empty-state">
                  <Bell className="empty-bell" size={48} />
                  <p>All caught up! No notifications yet.</p>
                </div>
              ) : (
                <ul className="noti-list">
                  {notifications.map((noti) => (
                    <li
                      key={noti.id}
                      className={`noti-list-item ${noti.is_read ? 'read' : 'unread'}`}
                      onClick={() => !noti.is_read && handleMarkAsRead(noti.id)}
                    >
                      <div className="noti-item-header">
                        {getIcon(noti.type)}
                        <span className="noti-item-title">{noti.title}</span>
                        {!noti.is_read && (
                          <span className="unread-dot" />
                        )}
                      </div>
                      <p className="noti-item-message">{noti.message}</p>
                      <div className="noti-item-footer">
                        <span>{new Date(noti.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
                        {!noti.is_read && (
                          <span className="mark-read-hint">Click to dismiss</span>
                        )}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </aside>
        </div>
      )}
    </>
  );
}
