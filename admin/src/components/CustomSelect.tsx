import React, { useState, useRef, useEffect } from 'react';

interface Option {
  value: string | number;
  label: string;
}

interface CustomSelectProps {
  options: Option[];
  value: string | number;
  onChange: (value: any) => void;
  placeholder?: string;
  style?: React.CSSProperties;
}

export default function CustomSelect({ options, value, onChange, placeholder, style }: CustomSelectProps) {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const selectedOption = options.find(opt => opt.value === value);

  return (
    <div ref={containerRef} style={{ position: 'relative', ...style }}>
      {/* Trigger */}
      <div
        onClick={() => setIsOpen(!isOpen)}
        style={{
          width: '100%',
          padding: '12px 16px',
          background: '#ffffff',
          border: isOpen ? '1.5px solid var(--color-primary)' : '1px solid var(--border-color)',
          borderRadius: '10px',
          color: 'var(--text-dark)',
          fontSize: '14px',
          cursor: 'pointer',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          userSelect: 'none',
          boxShadow: isOpen ? '0 0 12px rgba(37, 99, 235, 0.15)' : 'none',
          transition: 'all 0.15s ease'
        }}
      >
        <span style={{ color: selectedOption ? 'var(--text-dark)' : 'var(--text-muted)', textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap', fontWeight: 500 }}>
          {selectedOption ? selectedOption.label : (placeholder || '-- Choose --')}
        </span>
        <span style={{ 
          fontSize: '9px', 
          color: 'var(--text-muted)', 
          marginLeft: '8px',
          transition: 'transform 0.2s', 
          transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)' 
        }}>
          ▼
        </span>
      </div>

      {/* Options List */}
      {isOpen && (
        <div
          style={{
            position: 'absolute',
            top: '100%',
            left: 0,
            right: 0,
            marginTop: '6px',
            background: '#ffffff',
            border: '1px solid var(--border-color)',
            borderRadius: '12px',
            boxShadow: '0 10px 30px rgba(10, 37, 64, 0.08)',
            zIndex: 1010,
            maxHeight: '220px',
            overflowY: 'auto',
            padding: '4px'
          }}
        >
          {options.map(opt => {
            const isSelected = value === opt.value;
            return (
              <div
                key={opt.value}
                onClick={() => {
                  onChange(opt.value);
                  setIsOpen(false);
                }}
                onMouseEnter={(e) => {
                  if (!isSelected) {
                    e.currentTarget.style.background = 'rgba(37, 99, 235, 0.05)';
                    e.currentTarget.style.color = 'var(--color-primary)';
                  }
                }}
                onMouseLeave={(e) => {
                  if (!isSelected) {
                    e.currentTarget.style.background = 'transparent';
                    e.currentTarget.style.color = 'var(--text-dark)';
                  }
                }}
                style={{
                  padding: '10px 14px',
                  borderRadius: '8px',
                  background: isSelected ? 'var(--color-primary)' : 'transparent',
                  color: isSelected ? 'white' : 'var(--text-dark)',
                  cursor: 'pointer',
                  fontSize: '13px',
                  fontWeight: isSelected ? 600 : 500,
                  transition: 'all 0.15s ease',
                  textAlign: 'left',
                  marginBottom: '2px'
                }}
              >
                {opt.label}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
