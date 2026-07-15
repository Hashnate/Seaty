import React, { createContext, useContext, useState, useCallback } from 'react';
import { loginAdmin, getCurrentUser } from '../api/client';

interface AuthState {
  token: string | null;
  user: Record<string, unknown> | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  isLoading: boolean;
  error: string | null;
}

const AuthContext = createContext<AuthState>({
  token: null,
  user: null,
  login: async () => {},
  logout: () => {},
  isLoading: false,
  error: null,
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [token, setToken] = useState<string | null>(() => {
    try {
      return localStorage.getItem('seaty_token');
    } catch (e) {
      console.error('Failed to get seaty_token from localStorage:', e);
      return null;
    }
  });
  const [user, setUser] = useState<Record<string, unknown> | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const logout = useCallback(() => {
    setToken(null);
    setUser(null);
    try {
      localStorage.removeItem('seaty_token');
    } catch (e) {
      console.error('Failed to remove seaty_token from localStorage:', e);
    }
  }, []);

  React.useEffect(() => {
    if (token && !user) {
      setIsLoading(true);
      getCurrentUser(token)
        .then(userData => {
          setUser(userData as Record<string, unknown>);
        })
        .catch(() => {
          logout();
        })
        .finally(() => {
          setIsLoading(false);
        });
    }
  }, [token, user, logout]);

  const login = useCallback(async (email: string, password: string) => {
    setIsLoading(true);
    setError(null);
    try {
      const data = await loginAdmin(email, password) as { access_token: string };
      setToken(data.access_token);
      try {
        localStorage.setItem('seaty_token', data.access_token);
      } catch (e) {
        console.error('Failed to set seaty_token in localStorage:', e);
      }
      
      const userData = await getCurrentUser(data.access_token);
      setUser(userData as Record<string, unknown>);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
      throw err;
    } finally {
      setIsLoading(false);
    }
  }, []);

  return (
    <AuthContext.Provider value={{ token, user, login, logout, isLoading, error }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
