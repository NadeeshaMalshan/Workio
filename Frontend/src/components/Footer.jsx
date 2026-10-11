import React, { useState } from 'react';
import './Footer.css';
import workioLogoWhite from '../assets/Workio_Logo/Workio_Logo_White_With_Text.png';
import androidApkBadge from '../assets/download-android-apk.png';

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


            {/* App Store / APK Download Badges */}
            <div className="uber-footer-app-badges">
              {/* Android APK Download Badge */}
              <a
                href="https://drive.google.com/drive/folders/1kHF2igKue5_j_IEn70Wc4cFsKpLUZRfZ?usp=drive_link"
                target="_blank"
                rel="noopener noreferrer"
                className="uber-app-badge-link"
                title="Download Workio Android APK"
              >
                <img
                  src={androidApkBadge}
                  alt="Download Workio Android APK"
                  className="uber-app-badge-img"
                />
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
            © 2026 Workio Inc.
          </div>


        </div>

      </div>
    </footer>
  );
}
