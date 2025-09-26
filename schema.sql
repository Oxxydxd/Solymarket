-- Solymarket Database Schema
-- Run this on your Render PostgreSQL database

-- Users table
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  wallet_address VARCHAR(44) UNIQUE NOT NULL,
  username VARCHAR(50),
  email VARCHAR(255),
  total_volume DECIMAL(20,8) DEFAULT 0,
  total_bets INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Markets table
CREATE TABLE markets (
  id SERIAL PRIMARY KEY,
  title VARCHAR(500) NOT NULL,
  description TEXT,
  category VARCHAR(50) NOT NULL DEFAULT 'other',
  creator_address VARCHAR(44) NOT NULL,
  
  -- Market mechanics
  initial_liquidity DECIMAL(20,8) NOT NULL,
  total_volume DECIMAL(20,8) DEFAULT 0,
  total_traders INTEGER DEFAULT 0,
  
  -- Timing
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  end_date TIMESTAMP NOT NULL,
  resolved_at TIMESTAMP,
  
  -- Status
  status VARCHAR(20) DEFAULT 'active', -- active, ended, resolved, cancelled
  winning_option_id INTEGER,
  
  -- Blockchain
  market_address VARCHAR(44), -- Solana program account
  creation_signature VARCHAR(88),
  
  -- Images
  market_image_url VARCHAR(500)
);

CREATE INDEX idx_markets_creator ON markets(creator_address);
CREATE INDEX idx_markets_status ON markets(status);
CREATE INDEX idx_markets_category ON markets(category);
CREATE INDEX idx_markets_end_date ON markets(end_date);

-- Market options (outcomes)
CREATE TABLE market_options (
  id SERIAL PRIMARY KEY,
  market_id INTEGER NOT NULL,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  
  -- Current state
  current_odds DECIMAL(5,4) NOT NULL DEFAULT 0.5000, -- 0.0000 to 1.0000
  current_price DECIMAL(8,4) NOT NULL DEFAULT 50.0000, -- Price in cents
  total_volume DECIMAL(20,8) DEFAULT 0,
  shares_outstanding BIGINT DEFAULT 0,
  
  -- Display
  avatar VARCHAR(10), -- Generated initials
  image_url VARCHAR(500),
  display_order INTEGER DEFAULT 0,
  
  -- Results
  is_winning_option BOOLEAN DEFAULT FALSE,
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (market_id) REFERENCES markets(id) ON DELETE CASCADE
);

CREATE INDEX idx_market_options_market ON market_options(market_id);
CREATE INDEX idx_market_options_odds ON market_options(current_odds);

-- User bets/positions
CREATE TABLE bets (
  id SERIAL PRIMARY KEY,
  user_address VARCHAR(44) NOT NULL,
  market_id INTEGER NOT NULL,
  option_id INTEGER NOT NULL,
  
  -- Bet details
  bet_type VARCHAR(10) NOT NULL, -- 'buy' or 'sell'
  amount DECIMAL(20,8) NOT NULL, -- Amount in SOL/USDC
  shares BIGINT NOT NULL, -- Number of shares purchased
  price_per_share DECIMAL(8,4) NOT NULL, -- Price paid per share in cents
  
  -- Blockchain
  transaction_signature VARCHAR(88) NOT NULL,
  block_time TIMESTAMP,
  
  -- Status
  status VARCHAR(20) DEFAULT 'active', -- active, claimed, cancelled
  payout_amount DECIMAL(20,8), -- Final payout when resolved
  payout_signature VARCHAR(88), -- Payout transaction
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  FOREIGN KEY (market_id) REFERENCES markets(id),
  FOREIGN KEY (option_id) REFERENCES market_options(id)
);

CREATE INDEX idx_bets_user ON bets(user_address);
CREATE INDEX idx_bets_market ON bets(market_id);
CREATE INDEX idx_bets_option ON bets(option_id);
CREATE INDEX idx_bets_signature ON bets(transaction_signature);
CREATE INDEX idx_bets_status ON bets(status);

-- Market activity/price history for charts
CREATE TABLE market_activity (
  id SERIAL PRIMARY KEY,
  market_id INTEGER NOT NULL,
  option_id INTEGER NOT NULL,
  
  -- Price point
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  price DECIMAL(8,4) NOT NULL, -- Price in cents at this time
  odds DECIMAL(5,4) NOT NULL, -- Odds (0.0000-1.0000) at this time
  volume_24h DECIMAL(20,8) DEFAULT 0, -- 24h volume at this point
  
  -- Aggregation level
  timeframe VARCHAR(10) NOT NULL, -- '1m', '5m', '1h', '1d'
  
  FOREIGN KEY (market_id) REFERENCES markets(id) ON DELETE CASCADE,
  FOREIGN KEY (option_id) REFERENCES market_options(id) ON DELETE CASCADE
);

CREATE INDEX idx_market_activity_market_time ON market_activity(market_id, timestamp);
CREATE INDEX idx_market_activity_option_time ON market_activity(option_id, timestamp);
CREATE INDEX idx_market_activity_timeframe ON market_activity(timeframe);

-- Transactions log for audit trail
CREATE TABLE transactions (
  id SERIAL PRIMARY KEY,
  signature VARCHAR(88) UNIQUE NOT NULL,
  transaction_type VARCHAR(50) NOT NULL, -- 'create_market', 'place_bet', 'resolve_market', 'claim_payout'
  
  -- References
  user_address VARCHAR(44),
  market_id INTEGER,
  bet_id INTEGER,
  
  -- Transaction details
  amount DECIMAL(20,8), -- Amount involved
  fee DECIMAL(20,8), -- Platform fee
  status VARCHAR(20) DEFAULT 'pending', -- pending, confirmed, failed
  block_slot BIGINT,
  block_time TIMESTAMP,
  
  -- Raw data
  raw_transaction TEXT, -- Store full transaction data
  error_message TEXT,
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  confirmed_at TIMESTAMP
);

CREATE INDEX idx_transactions_signature ON transactions(signature);
CREATE INDEX idx_transactions_user ON transactions(user_address);
CREATE INDEX idx_transactions_market ON transactions(market_id);
CREATE INDEX idx_transactions_type ON transactions(transaction_type);
CREATE INDEX idx_transactions_status ON transactions(status);

-- Platform stats and treasury
CREATE TABLE platform_stats (
  id SERIAL PRIMARY KEY,
  date DATE UNIQUE NOT NULL,
  
  -- Daily metrics
  daily_volume DECIMAL(20,8) DEFAULT 0,
  daily_trades INTEGER DEFAULT 0,
  daily_new_users INTEGER DEFAULT 0,
  daily_new_markets INTEGER DEFAULT 0,
  
  -- Cumulative metrics
  total_volume DECIMAL(20,8) DEFAULT 0,
  total_trades INTEGER DEFAULT 0,
  total_users INTEGER DEFAULT 0,
  total_markets INTEGER DEFAULT 0,
  
  -- Treasury
  treasury_balance DECIMAL(20,8) DEFAULT 0,
  fees_collected DECIMAL(20,8) DEFAULT 0,
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User sessions for analytics
CREATE TABLE user_sessions (
  id SERIAL PRIMARY KEY,
  user_address VARCHAR(44) NOT NULL,
  session_id VARCHAR(128) NOT NULL,
  
  -- Session data
  ip_address INET,
  user_agent TEXT,
  referrer VARCHAR(500),
  
  -- Timing
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  ended_at TIMESTAMP
);

CREATE INDEX idx_user_sessions_user ON user_sessions(user_address);
CREATE INDEX idx_user_sessions_session ON user_sessions(session_id);
CREATE INDEX idx_user_sessions_activity ON user_sessions(last_activity);

-- Create some useful views
CREATE VIEW active_markets AS
SELECT 
  m.*,
  COUNT(DISTINCT b.user_address) as unique_traders,
  COUNT(b.id) as total_bets,
  COALESCE(SUM(b.amount), 0) as calculated_volume
FROM markets m
LEFT JOIN bets b ON m.id = b.market_id AND b.status = 'active'
WHERE m.status = 'active' AND m.end_date > NOW()
GROUP BY m.id;

CREATE VIEW user_stats AS
SELECT 
  u.wallet_address,
  u.username,
  COUNT(DISTINCT b.market_id) as markets_participated,
  COUNT(b.id) as total_bets,
  COALESCE(SUM(b.amount), 0) as total_volume,
  COALESCE(SUM(CASE WHEN b.payout_amount IS NOT NULL THEN b.payout_amount - b.amount ELSE 0 END), 0) as total_pnl,
  u.created_at
FROM users u
LEFT JOIN bets b ON u.wallet_address = b.user_address
GROUP BY u.wallet_address, u.username, u.created_at;

-- Insert initial data
INSERT INTO platform_stats (date, treasury_balance) VALUES (CURRENT_DATE, 0);

-- Trigger to update market volume
CREATE OR REPLACE FUNCTION update_market_volume()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE markets 
  SET 
    total_volume = (
      SELECT COALESCE(SUM(amount), 0) 
      FROM bets 
      WHERE market_id = NEW.market_id AND status = 'active'
    ),
    total_traders = (
      SELECT COUNT(DISTINCT user_address) 
      FROM bets 
      WHERE market_id = NEW.market_id AND status = 'active'
    )
  RETURN NEW;
END;
$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_market_volume
  AFTER INSERT OR UPDATE ON bets
  FOR EACH ROW
  EXECUTE FUNCTION update_market_volume();

-- Trigger to update option volume
CREATE OR REPLACE FUNCTION update_option_volume()
RETURNS TRIGGER AS $
BEGIN
  UPDATE market_options 
  SET total_volume = (
    SELECT COALESCE(SUM(amount), 0) 
    FROM bets 
    WHERE option_id = NEW.option_id AND status = 'active'
  )
  WHERE id = NEW.option_id;
  
  RETURN NEW;
END;
$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_option_volume
  AFTER INSERT OR UPDATE ON bets
  FOR EACH ROW
  EXECUTE FUNCTION update_option_volume();
