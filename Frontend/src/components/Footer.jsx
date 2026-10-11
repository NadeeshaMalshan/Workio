import React, { useState } from 'react';
import './Footer.css';
import workioLogoWhite from '../assets/Workio_Logo/Workio_Logo_White_With_Text.png';

export default function Footer() {
  const [selectedLanguage, setSelectedLanguage] = useState('English');
  const [isLangOpen, setIsLangOpen] = useState(false);

  const navigate = (path) => {
    window.history.pushState({}, '', path);
    window.dispatchEvent(new PopStateEvent('popstate'));
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  return (
    <footer className="uber-footer-wrapper">
      <div className="uber-footer-container">

        {/* Top Brand & Help Header */}
        <div className="uber-footer-top">
          <div className="uber-footer-brand" onClick={() => navigate('/')} title="Workio - Home">
            <img src={workioLogoWhite} alt="Workio" className="uber-footer-logo-img" />
          </div>
          <a
            href="/community"
            className="uber-footer-help-link"
            onClick={(e) => {
              e.preventDefault();
              navigate('/community');
            }}
          >
            Visit Help & Community Center
          </a>
        </div>

        {/* 4 Multi-Column Directory */}
        <div className="uber-footer-columns">


          {/* Column 1: Products / Services */}
          <div className="uber-footer-col">
            <h4 className="uber-footer-col-title">Services</h4>
            <ul className="uber-footer-links-list">
              <li><a href="/find" onClick={(e) => { e.preventDefault(); navigate('/find'); }}>Hire a Baas</a></li>
              <li><a href="/join" onClick={(e) => { e.preventDefault(); navigate('/join'); }}>Become a Baas / Pro</a></li>

              <li><a href="/ai/chat" onClick={(e) => { e.preventDefault(); navigate(localStorage.getItem('token') ? '/ai/chat' : '/join'); }}>Workio AI</a></li>
              <li><a href="/community" onClick={(e) => { e.preventDefault(); navigate('/community'); }}>Community Hub</a></li>
              <li><a href="/find?q=Emergency" onClick={(e) => { e.preventDefault(); navigate('/find?q=Emergency'); }}>Emergency Repairs</a></li>

            </ul>
          </div>




          {/* Column 2: Coverage / Locations */}
          <div className="uber-footer-col">
            <h4 className="uber-footer-col-title">Locations</h4>
            <ul className="uber-footer-links-list">
              <li><a href="/find?location=Colombo" onClick={(e) => { e.preventDefault(); navigate('/find?location=Colombo'); }}>Colombo</a></li>
              <li><a href="/find?location=Kandy" onClick={(e) => { e.preventDefault(); navigate('/find?location=Kandy'); }}>Kandy</a></li>
              <li><a href="/find?location=Galle" onClick={(e) => { e.preventDefault(); navigate('/find?location=Galle'); }}>Galle</a></li>
              <li><a href="/find?location=Gampaha" onClick={(e) => { e.preventDefault(); navigate('/find?location=Gampaha'); }}>Gampaha</a></li>
              <li><a href="/find?location=Negombo" onClick={(e) => { e.preventDefault(); navigate('/find?location=Negombo'); }}>Negombo</a></li>
              <li><a href="/find?location=Kurunegala" onClick={(e) => { e.preventDefault(); navigate('/find?location=Kurunegala'); }}>Kurunegala</a></li>
              <li><a href="/find" onClick={(e) => { e.preventDefault(); navigate('/find'); }}>All Cities & Regions</a></li>
            </ul>
          </div>
        </div>

        {/* Middle Utility & Social Row */}
        <div className="uber-footer-middle">
          {/* Left: Social Icons & App Badges */}
          <div className="uber-footer-social-and-apps">


            {/* App Store Download Badges */}
            <div className="uber-footer-app-badges">
              {/* Google Play Store Badge */}
              <a
                href="https://drive.google.com/drive/folders/1kHF2igKue5_j_IEn70Wc4cFsKpLUZRfZ?usp=drive_link"
                target="_blank"
                rel="noopener noreferrer"
                className="uber-app-badge-btn"
                title="Download Workio on Google Play"
              >
                <svg className="uber-badge-icon" viewBox="0 0 24 24" width="22" height="22">
                  <path fill="#4285F4" d="M3.6 2.4l10.8 10.8L3.6 24c-.4-.5-.6-1.2-.6-2V4.4c0-.8.2-1.5.6-2z" />
                  <path fill="#FBBC05" d="M17.8 8.8l-3.4 3.4L3.6 2.4c.4-.4 1-.5 1.6-.2l12.6 6.6z" />
                  <path fill="#34A853" d="M17.8 15.2L5.2 21.8c-.6.3-1.2.2-1.6-.2l10.8-10.8 3.4 3.4z" />
                  <path fill="#EA4335" d="M21.6 10.8c.5.3.8.8.8 1.2s-.3.9-.8 1.2l-3.8 2-3.4-3.2 3.4-3.2 3.8 2z" />
                </svg>
                <div className="uber-badge-text-wrap">
                  <span className="uber-badge-sub">GET IT ON</span>
                  <span className="uber-badge-title">Google Play</span>
                </div>
              </a>

            </div>
          </div>

          {/* Right: Language & Location Selector */}
          <div className="uber-footer-locales">
            {/* Language Selector */}
            <div className="uber-locale-pill-wrapper">
              <button
                type="button"
                className="uber-locale-pill"
                onClick={() => setIsLangOpen(prev => !prev)}
                aria-label="Select Language"
              >
                <span className="uber-locale-text">{selectedLanguage}</span>
              </button>

              {isLangOpen && (
                <div className="uber-locale-dropdown">
                  {['English', 'සිංහල (Sinhala)', 'தமிழ் (Tamil)'].map((lang) => (
                    <div
                      key={lang}
                      className={`uber-locale-option ${selectedLanguage === lang.split(' ')[0] ? 'active' : ''}`}
                      onClick={() => {
                        setSelectedLanguage(lang.split(' ')[0]);
                        setIsLangOpen(false);
                      }}
                    >
                      {lang}
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Location Pill */}
            <div className="uber-locale-pill-wrapper">
              <button
                type="button"
                className="uber-locale-pill"
                onClick={() => navigate('/find')}
                aria-label="Current Region"
              >
                <span className="uber-locale-text">LK</span>
              </button>
            </div>
          </div>
        </div>

        {/* Bottom Legal & Copyright Row */}
        <div className="uber-footer-bottom">
          <div className="uber-footer-copyright">
            © 2026 Workio Technologies Inc.
          </div>

          <div className="uber-footer-legal-links">
            <a href="#privacy" onClick={(e) => { e.preventDefault(); navigate('/community'); }}>Privacy</a>
            <a href="#accessibility" onClick={(e) => { e.preventDefault(); navigate('/community'); }}>Accessibility</a>
            <a href="#terms" onClick={(e) => { e.preventDefault(); navigate('/community'); }}>Terms</a>
          </div>
        </div>

      </div>
    </footer>
  );
}
