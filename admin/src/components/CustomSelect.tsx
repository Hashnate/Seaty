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
          background: '#1e293b',
          border: isOpen ? '1.5px solid #e65100' : '1px solid rgba(255,255,255,0.1)',
          borderRadius: '10px',
          color: 'white',
          fontSize: '14px',
          cursor: 'pointer',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          userSelect: 'none',
          boxShadow: isOpen ? '0 0 12px rgba(230, 81, 0, 0.25)' : 'none',
          transition: 'all 0.15s ease'
        }}
      >
        <span style={{ color: selectedOption ? 'white' : 'rgba(255,255,255,0.4)', textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap' }}>
          {selectedOption ? selectedOption.label : (placeholder || '-- Choose --')}
        </span>
        <span style={{ 
          fontSize: '9px', 
          color: 'rgba(255,255,255,0.4)', 
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
            background: '#0b0f19',
            border: '1px solid rgba(255,255,255,0.12)',
            borderRadius: '10px',
            boxShadow: '0 10px 25px -5px rgba(0, 0, 0, 0.5)',
            zIndex: 1010,
            maxHeight: '220px',
            overflowY: 'auto'
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
                    e.currentTarget.style.background = 'rgba(230, 81, 0, 0.08)';
                  }
                }}
                onMouseLeave={(e) => {
                  if (!isSelected) {
                    e.currentTarget.style.background = 'transparent';
                  }
                }}
                style={{
                  padding: '12px 16px',
                  background: isSelected ? '#e65100' : 'transparent',
                  color: isSelected ? 'white' : 'rgba(255,255,255,0.8)',
                  cursor: 'pointer',
                  fontSize: '13.5px',
                  fontWeight: isSelected ? 600 : 400,
                  transition: 'all 0.15s ease',
                  textAlign: 'left'
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
