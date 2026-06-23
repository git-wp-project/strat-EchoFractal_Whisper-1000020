//+------------------------------------------------------------------+
//|                    EchoFractal Whisper Protocol EA               |
//|              Professional Quantitative Trading System            |
//|  Alternative Reversal System using Fractals + RSI + ADX + Volume |
//|                 For MT5 - Executable Complete EA                 |
//+------------------------------------------------------------------+
#property copyright "Quant Strategy Builder | Grok 4.3 Dynamic Model"
#property link      "Professional Use Only"
#property version   "1.00"
#property strict
#property description "EchoFractal Whisper Protocol - An alternative market participation scheme focusing on quiet accumulation echoes before reversals. Uses Bill Williams Fractals confirmed by RSI momentum shift in low ADX environments with volume surge."
#property indicator_buffers 0

#include <Trade\Trade.mqh>
CTrade trade;

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
input ulong  Magic_Number        = 20260505;    // Unique Magic Number | 魔法编号 (用于识别此方案订单)

input group           "Volume Confirmation Filter | 成交量确认过滤"
input bool   Use_Volume_Filter   = true;        // Enable volume surge confirmation | 启用成交量 surge 确认 (另类特征)
input int    Volume_MA_Period    = 20;          // Volume moving average period | 成交量均线周期

input group           "Execution Filters | 执行过滤器"
input int    Min_Bars_Between    = 10;          // Minimum bars between opportunities | 两次参与机会间最小K线数 (避免过度)
input bool   TradeOnNewBarOnly   = true;        // Execute only on new bar open | 仅在新K线开盘时执行 (推荐开启)

//========================== GLOBAL VARIABLES ==========================
datetime g_LastBarTime = 0;
int      g_LastTradeBar = 0;
double   g_Point = 0;

//========================== INDICATOR HANDLES ==========================
int rsi_handle     = INVALID_HANDLE;
int adx_handle     = INVALID_HANDLE;
int atr_handle     = INVALID_HANDLE;
int fractal_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   g_Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(g_Point == 0) g_Point = 0.00001;
   
   if(RSI_Period <= 0 || ADX_Period <= 0 || ATR_Period <= 0)
     {
      Print("Invalid indicator periods. Please check parameters.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   
   // Create indicator handles
   rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   if(rsi_handle == INVALID_HANDLE)
     {
      Print("Failed to create RSI indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }
   
   adx_handle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
   if(adx_handle == INVALID_HANDLE)
     {
      Print("Failed to create ADX indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }
   
   atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(atr_handle == INVALID_HANDLE)
     {
      Print("Failed to create ATR indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }
   
   fractal_handle = iFractals(_Symbol, PERIOD_CURRENT);
   if(fractal_handle == INVALID_HANDLE)
     {
      Print("Failed to create Fractals indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }
   
   Print("EchoFractal Whisper Protocol EA (MT5) initialized successfully. | 回音分形低语协议EA(MT5)初始化成功");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Release indicator handles
   if(rsi_handle != INVALID_HANDLE)     IndicatorRelease(rsi_handle);
   if(adx_handle != INVALID_HANDLE)     IndicatorRelease(adx_handle);
   if(atr_handle != INVALID_HANDLE)     IndicatorRelease(atr_handle);
   if(fractal_handle != INVALID_HANDLE) IndicatorRelease(fractal_handle);
   
   Print("EchoFractal Whisper Protocol EA deinitialized. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Check if new bar opened                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar != g_LastBarTime)
     {
      g_LastBarTime = currentBar;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Calculate position lot size based on risk (MT5 version)          |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLossPrice)
  {
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (Risk_Percent / 100.0);
   
   double slDistancePoints = MathAbs(entryPrice - stopLossPrice) / g_Point;
   if(slDistancePoints <= 0) return(0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0) tickValue = 1;
   
   double rawLot = riskAmount / (slDistancePoints * tickValue);
   
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong posTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(posTicket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == Magic_Number && 
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Main entry checking logic (MT5)                                  |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
  {
   if(HasOpenPosition()) return;
   
   if(TradeOnNewBarOnly && !IsNewBar()) return;
   if(Bars(_Symbol, PERIOD_CURRENT) - g_LastTradeBar < Min_Bars_Between) return;
   
   // === Get Indicator Values via handles ===
   double rsi_buffer[2];
   if(CopyBuffer(rsi_handle, 0, 1, 2, rsi_buffer) != 2)
     {
      Print("Failed to copy RSI buffer");
      return;
     }
   double rsiCurrent = rsi_buffer[0];
   double rsiPrev    = rsi_buffer[1];
   
   double adx_buffer[1];
   if(CopyBuffer(adx_handle, 0, 1, 1, adx_buffer) != 1)
     {
      Print("Failed to copy ADX buffer");
      return;
     }
   double adxCurrent = adx_buffer[0];
   
   double atr_buffer[1];
   if(CopyBuffer(atr_handle, 0, 1, 1, atr_buffer) != 1)
     {
      Print("Failed to copy ATR buffer");
      return;
     }
   double atrCurrent = atr_buffer[0];
   
   double volCurrent = (double)iVolume(_Symbol, PERIOD_CURRENT, 1);
   double volMA = 0;
   if(Use_Volume_Filter)
     {
      for(int i = 1; i <= Volume_MA_Period; i++)
         volMA += (double)iVolume(_Symbol, PERIOD_CURRENT, i);
      volMA /= Volume_MA_Period;
     }
   
   // === Fractal Detection ===
   double bullFractal = 0.0;
   double bearFractal = 0.0;
   double frac_buffer[1];
   
   if(CopyBuffer(fractal_handle, 1, 2, 1, frac_buffer) == 1) // LOWER = bullish fractals
     {
      if(frac_buffer[0] != EMPTY_VALUE)
         bullFractal = frac_buffer[0];
     }
   
   if(CopyBuffer(fractal_handle, 0, 2, 1, frac_buffer) == 1) // UPPER = bearish fractals
     {
      if(frac_buffer[0] != EMPTY_VALUE)
         bearFractal = frac_buffer[0];
     }
   
   MqlTick latestTick;
   if(!SymbolInfoTick(_Symbol, latestTick)) return;
   double ask = latestTick.ask;
   double bid = latestTick.bid;
   
   // === LONG / BUY Opportunity ===
   if(bullFractal > 0 && 
      rsiCurrent < RSI_Long_Threshold && 
      rsiCurrent > rsiPrev && 
      adxCurrent < ADX_Threshold)
     {
      if(Use_Volume_Filter && volCurrent < volMA * 1.1) return;
      
      double entry = ask;
      double sl    = bullFractal - (atrCurrent * SL_ATR_Multiplier);
      double risk  = entry - sl;
      if(risk <= 0) return;
      double tp    = entry + (risk * TP_Risk_Reward);
      
      double lot = CalculateLotSize(entry, sl);
      if(lot <= 0) return;
      
      if(trade.Buy(lot, _Symbol, entry, sl, tp, "EchoFractal_Whisper_LONG"))
        {
         Print("LONG opportunity executed | 买入计划已执行 @ ", entry);
         g_LastTradeBar = Bars(_Symbol, PERIOD_CURRENT);
        }
     }
   
   // === SHORT / SELL Opportunity ===
   if(bearFractal > 0 && 
      rsiCurrent > RSI_Short_Threshold && 
      rsiCurrent < rsiPrev && 
      adxCurrent < ADX_Threshold)
     {
      if(Use_Volume_Filter && volCurrent < volMA * 1.1) return;
      
      double entry = bid;
      double sl    = bearFractal + (atrCurrent * SL_ATR_Multiplier);
      double risk  = sl - entry;
      if(risk <= 0) return;
      double tp    = entry - (risk * TP_Risk_Reward);
      
      double lot = CalculateLotSize(entry, sl);
      if(lot <= 0) return;
      
      if(trade.Sell(lot, _Symbol, entry, sl, tp, "EchoFractal_Whisper_SHORT"))
        {
         Print("SHORT opportunity executed | 卖出计划已执行 @ ", entry);
         g_LastTradeBar = Bars(_Symbol, PERIOD_CURRENT);
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function (MT5)                                       |
//+------------------------------------------------------------------+
void OnTick()
  {
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
//| End of EchoFractal Whisper Protocol EA for MT5                   |
//| Complete executable alternative participation scheme             |
//| Recommended timeframe: H1 or H4 on major forex pairs             |
//+------------------------------------------------------------------+