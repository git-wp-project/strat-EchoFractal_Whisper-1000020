//+------------------------------------------------------------------+
//|                    EchoFractal Whisper Protocol EA               |
//|              Professional Quantitative Trading System            |
//|  Alternative Reversal System using Fractals + RSI + ADX + Volume |
//|                 For MT4 - Executable Complete EA                 |
//+------------------------------------------------------------------+
#property copyright "Quant Strategy Builder | Grok 4.3 Dynamic Model"
#property link      "Professional Use Only"
#property version   "1.00"
#property strict
#property description "EchoFractal Whisper Protocol - An alternative market participation scheme focusing on quiet accumulation echoes before reversals. Uses Bill Williams Fractals confirmed by RSI momentum shift in low ADX environments with volume surge."

//========================== INPUT PARAMETERS ==========================
// All parameters with concise bilingual remarks for easy setup
input group           "Core Indicator Settings | 核心指标设置"
input int    RSI_Period          = 14;          // RSI Period | RSI周期 (default 14)
input int    ADX_Period          = 14;          // ADX Period | ADX周期 (default 14)
input int    ATR_Period          = 14;          // ATR Period for SL/TP | ATR周期用于止损止盈
input double ADX_Threshold       = 25.0;        // Max ADX for "quiet" ranging market | ADX盘整阈值 (低ADX表示安静市场)
input double RSI_Long_Threshold  = 40.0;        // RSI level for long opportunities | RSI参与机会阈值 (低于此值考虑买入)
input double RSI_Short_Threshold = 60.0;        // RSI level for short opportunities | RSI观望机会阈值 (高于此值考虑卖出)

input group           "Risk & Position Management | 风险与仓位管理"
input double Risk_Percent        = 1.0;         // Risk % of account per opportunity | 每笔计划风险百分比 (推荐1%)
input double SL_ATR_Multiplier   = 1.5;         // Stop Loss distance as ATR multiple | 止损距离 (ATR倍数)
input double TP_Risk_Reward      = 2.5;         // Take Profit Risk-Reward ratio | 止盈盈亏比 (推荐2.5:1)
input int    Magic_Number        = 20260505;    // Unique Magic Number | 魔法编号 (用于识别此方案订单)

input group           "Volume Confirmation Filter | 成交量确认过滤"
input bool   Use_Volume_Filter   = true;        // Enable volume surge confirmation | 启用成交量 surge 确认 (另类特征)
input int    Volume_MA_Period    = 20;          // Volume moving average period | 成交量均线周期

input group           "Execution Filters | 执行过滤器"
input int    Min_Bars_Between    = 10;          // Minimum bars between opportunities | 两次参与机会间最小K线数 (避免过度)
input bool   TradeOnNewBarOnly   = true;        // Execute only on new bar open | 仅在新K线开盘时执行 (推荐开启)

//========================== GLOBAL VARIABLES ==========================
int    g_MagicNumber = Magic_Number;
datetime g_LastBarTime = 0;
int    g_LastTradeBar = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Validate inputs
   if(RSI_Period <= 0 || ADX_Period <= 0 || ATR_Period <= 0)
     {
      Print("Invalid indicator periods. Please check parameters.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(Risk_Percent <= 0 || Risk_Percent > 10)
     {
      Print("Risk_Percent should be between 0.1 and 10.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   Print("EchoFractal Whisper Protocol EA initialized successfully. | 回音分形低语协议EA初始化成功");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EchoFractal Whisper Protocol EA deinitialized. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Check if new bar opened                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime currentBar = iTime(NULL, PERIOD_CURRENT, 0);
   if(currentBar != g_LastBarTime)
     {
      g_LastBarTime = currentBar;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Calculate position lot size based on risk                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLossPrice)
  {
   double accountBalance = AccountBalance();
   double riskAmount = accountBalance * (Risk_Percent / 100.0);
   
   double slDistancePoints = MathAbs(entryPrice - stopLossPrice) / Point;
   if(slDistancePoints <= 0) return(0);
   
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickValue <= 0) tickValue = 1; // safety
   
   double rawLot = riskAmount / (slDistancePoints * tickValue);
   
   // Normalize to broker lot step
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   
   double normalizedLot = MathFloor(rawLot / lotStep) * lotStep;
   
   if(normalizedLot < minLot) normalizedLot = minLot;
   if(normalizedLot > maxLot) normalizedLot = maxLot;
   
   return(normalizedLot);
  }

//+------------------------------------------------------------------+
//| Check if there is already an open position for this magic        |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderMagicNumber() == g_MagicNumber && OrderSymbol() == Symbol())
            return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Main entry checking logic                                        |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
  {
   if(HasOpenPosition()) return;
   
   // Only trade on new bar if enabled
   if(TradeOnNewBarOnly && !IsNewBar()) return;
   
   // Cooldown filter
   if(Bars - g_LastTradeBar < Min_Bars_Between) return;
   
   // === Get Indicator Values ===
   double rsiCurrent   = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsiPrev      = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);
   double adxCurrent   = iADX(NULL, 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   double atrCurrent   = iATR(NULL, 0, ATR_Period, 1);
   
   // Volume filter calculation (simple MA)
   double volCurrent = iVolume(NULL, 0, 1);
   double volMA = 0;
   if(Use_Volume_Filter)
     {
      for(int i=1; i<=Volume_MA_Period; i++)
         volMA += iVolume(NULL, 0, i);
      volMA /= Volume_MA_Period;
     }
   
   // === Fractal Detection ===
   double bullFractal = iFractals(NULL, 0, MODE_LOWER, 2);  // Bullish fractal (local low) at shift 2
   double bearFractal = iFractals(NULL, 0, MODE_UPPER, 2);  // Bearish fractal (local high) at shift 2
   
   // === LONG / BUY Opportunity (参与机会) ===
   if(bullFractal > 0 && 
      rsiCurrent < RSI_Long_Threshold && 
      rsiCurrent > rsiPrev &&                    // RSI rising from low (momentum echo)
      adxCurrent < ADX_Threshold)                // Quiet / ranging market
     {
      if(Use_Volume_Filter && volCurrent < volMA * 1.1) return; // Require volume confirmation (surge)
      
      double entry = Ask;
      double sl    = bullFractal - (atrCurrent * SL_ATR_Multiplier);  // Place SL below the fractal echo level
      double risk  = entry - sl;
      if(risk <= 0) return;
      double tp    = entry + (risk * TP_Risk_Reward);
      
      double lot = CalculateLotSize(entry, sl);
      if(lot <= 0) return;
      
      int ticket = OrderSend(Symbol(), OP_BUY, lot, entry, 3, sl, tp, 
                             "EchoFractal_Whisper_LONG", g_MagicNumber, 0, clrLimeGreen);
      if(ticket > 0)
        {
         Print("LONG opportunity executed | 买入计划已执行 @ ", entry, " SL:", sl, " TP:", tp);
         g_LastTradeBar = Bars;
        }
      else
         Print("OrderSend LONG failed. Error: ", GetLastError());
     }
   
   // === SHORT / SELL Opportunity (观望机会) ===
   if(bearFractal > 0 && 
      rsiCurrent > RSI_Short_Threshold && 
      rsiCurrent < rsiPrev &&                    // RSI falling from high
      adxCurrent < ADX_Threshold)
     {
      if(Use_Volume_Filter && volCurrent < volMA * 1.1) return;
      
      double entry = Bid;
      double sl    = bearFractal + (atrCurrent * SL_ATR_Multiplier);  // SL above bearish fractal
      double risk  = sl - entry;
      if(risk <= 0) return;
      double tp    = entry - (risk * TP_Risk_Reward);
      
      double lot = CalculateLotSize(entry, sl);
      if(lot <= 0) return;
      
      int ticket = OrderSend(Symbol(), OP_SELL, lot, entry, 3, sl, tp, 
                             "EchoFractal_Whisper_SHORT", g_MagicNumber, 0, clrRed);
      if(ticket > 0)
        {
         Print("SHORT opportunity executed | 卖出计划已执行 @ ", entry, " SL:", sl, " TP:", tp);
         g_LastTradeBar = Bars;
        }
      else
         Print("OrderSend SHORT failed. Error: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Only check on new bar to reduce noise (alternative clean execution)
   if(TradeOnNewBarOnly)
     {
      if(IsNewBar())
         CheckForEntrySignal();
     }
   else
     {
      CheckForEntrySignal();
     }
  }
//+------------------------------------------------------------------+
//| End of EchoFractal Whisper Protocol EA                           |
//| This is a complete, ready-to-compile alternative market plan EA  |
//| Backtest recommended on H1/H4 for major pairs.                   |
//+------------------------------------------------------------------+