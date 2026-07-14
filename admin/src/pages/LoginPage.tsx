import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';

export default function LoginPage() {
  const [email, setEmail] = useState('admin@seaty.lk');
  const [password, setPassword] = useState('password');
  const [localError, setLocalError] = useState('');
  const { login, isLoading } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLocalError('');
    try {
      await login(email, password);
      navigate('/');
    } catch {
      setLocalError('Invalid credentials. Make sure the backend is running and admin account exists.');
    }
  };

  return (
    <div className="auth-container">
      <div className="auth-card">
        <div className="auth-logo" style={{ display: 'flex', justifyContent: 'center', marginBottom: '16px' }}>
          <img src="/app_logo.png" alt="Seaty Logo" style={{ height: '48px', objectFit: 'contain' }} />
        </div>
        <p className="auth-subtitle">Luxury Transport Operator Admin Console</p>
        {localError && (
          <div style={{
            background: 'rgba(239, 68, 68, 0.08)',
            border: '1px solid rgba(239, 68, 68, 0.2)',
            borderRadius: '10px',
            padding: '10px 14px',
            fontSize: '13px',
            color: '#ef4444',
            marginBottom: '20px',
            textAlign: 'left'
          }}>
            {localError}
          </div>
        )}
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label">Email Address</label>
            <input
              type="email"
              className="form-input"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </div>
          <div className="form-group">
            <label className="form-label">Password</label>
            <input
              type="password"
              className="form-input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </div>
          <button type="submit" className="btn-primary" disabled={isLoading}>
            {isLoading ? 'Authenticating...' : 'Authenticate Console'}
          </button>
        </form>
      </div>
    </div>
  );
}
