//+------------------------------------------------------------------+
//| Merged by merge_ea.py - engine inlined, whitelabeled, gated.       |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//|                    EchoFractal Whisper Protocol EA               |
//|              Professional Quantitative Trading System            |
//|  Alternative Reversal System using Fractals + RSI + ADX + Volume |
//|                 For MT5 - Executable Complete EA                 |
//+------------------------------------------------------------------+
#property copyright "Quant Strategy Builder | Grok 4.3 Dynamic Model"
#property link      "Professional Use Only"
#property version   "1.00"
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


// ==================== EA 唯一序号 + 面板地址 (编译期常量) ====================
#define CT_EA_SERIAL "C023"
#define CT_SITE_URL  "https://jybj.org"

// ==================== CT 参数 (仅 CT_InviteCode 可见; 已取消 Token) ====================
input  string CT_InviteCode   = "";                    // 授权码 (XXXX-XXXX-XXXX)
sinput bool   CT_Enabled      = true;                  // 总开关(隐藏)
sinput int    CT_HeartbeatSec = 5;                     // 心跳间隔(隐藏)
sinput int    CT_MagicFilter  = 0;                     // 0=自动用 Magic_Number; 非零=自定义过滤(隐藏)
sinput bool   CT_ShowHUD      = true;                  // 图表显示授权到期 HUD(隐藏)

//+==================================================================+
//|  [ENGINE - inlined from .mqh, whitelabeled]                       |
//+==================================================================+


//+==================================================================+
//|  [STATE] 模块内部状态                                              |
//+==================================================================+
string    _CT_token        = "";
string    _CT_siteURL      = "";
int       _CT_heartbeatSec = 5;
int       _CT_magic        = 0;
bool      _CT_verbose      = false;

string    _CT_epHeartbeat  = "";
string    _CT_epBind       = "";
string    _CT_epValidate   = "";

string    _CT_groupId      = "";
string    _CT_stratName    = "";
string    _CT_expiry       = "";  // 授权到期日 YYYY-MM-DD (空=永久/未知)

datetime  _CT_lastHB       = 0;
datetime  _CT_lastVal      = 0;
datetime  _CT_lastScan     = 0;
bool      _CT_tokenValid   = true;
bool      _CT_active       = false;

int       _CT_lastPosCount = -1;
int       _CT_totalOpens   = 0;

ulong     _CT_reported[];
int       _CT_reportedCnt  = 0;
int       _CT_lastInitError = 0;  // 0=ok, 1=transient (network), 2=permanent (rejected)


//+==================================================================+
//|  [HTTP] HTTP 请求封装                                              |
//+==================================================================+
int _CT_HttpPostJson(string url, string json, string &outBody, int timeout = 5000) {
    char post[], resp[]; string respHeaders;
    int bytes = StringToCharArray(json, post, 0, WHOLE_ARRAY, CP_UTF8);
    if (bytes > 0 && post[bytes-1] == 0) ArrayResize(post, bytes-1);
    ResetLastError();
    int status = WebRequest("POST", url, "Content-Type: application/json\r\n",
                             timeout, post, resp, respHeaders);
    if (status < 0) {
        Print("[CT] POST 失败 err=", GetLastError(),
              "（请在 工具→选项→智能交易系统 中加入 ", _CT_siteURL, "）");
        outBody = "";
        return -1;
    }
    outBody = CharArrayToString(resp);
    return status;
}

string _CT_HttpGet(string url, int timeout = 5000) {
    char post[], resp[]; string respHeaders;
    ResetLastError();
    int status = WebRequest("GET", url, "", timeout, post, resp, respHeaders);
    if (status < 0) return "";
    return CharArrayToString(resp);
}

string _CT_JsonStr(string body, string key) {
    string pat = "\"" + key + "\":\"";
    int p = StringFind(body, pat);
    if (p < 0) return "";
    p += StringLen(pat);
    int e = StringFind(body, "\"", p);
    return e < 0 ? "" : StringSubstr(body, p, e - p);
}

bool _CT_JsonBool(string body, string key) {
    string pat = "\"" + key + "\":";
    int p = StringFind(body, pat);
    if (p < 0) return false;
    p += StringLen(pat);
    return StringSubstr(body, p, 4) == "true";
}


//+==================================================================+
//|  [BIND] 服务端绑定                                                 |
//+==================================================================+
bool _CT_Bind() {
    long   login  = (long) AccountInfoInteger(ACCOUNT_LOGIN);
    string server = AccountInfoString(ACCOUNT_SERVER);

    string j = "{";
    j += "\"token\":\""        + _CT_token              + "\",";
    j += "\"login\":\""        + IntegerToString(login) + "\",";
    j += "\"server\":\""       + server                 + "\",";
    j += "\"platform\":\"MT5\",";
    j += "\"account_type\":\"master\",";
    j += "\"ea_serial\":\"" + CT_EA_SERIAL + "\"";
    j += "}";

    string body;
    int status = _CT_HttpPostJson(_CT_epBind, j, body);
    if (status < 0) {
        Alert("⚠️ [EA] 无法连接面板：" + _CT_siteURL +
              "\n请检查 SiteURL 是否正确，以及是否在 工具→选项→智能交易系统 中加入了允许的 URL 列表。");
        _CT_lastInitError = 1;
        return false;
    }

    if (status >= 200 && status < 300 && _CT_JsonBool(body, "ok")) {
        _CT_groupId   = _CT_JsonStr(body, "group_id");
        _CT_stratName = _CT_JsonStr(body, "strategy_name");
        _CT_expiry    = _CT_JsonStr(body, "expiry");
        Print("[CT] ✅ 绑定成功 group_id=", _CT_groupId, " strategy=", _CT_stratName);
        return true;
    }

    string errCode = _CT_JsonStr(body, "code");
    string errMsg  = _CT_JsonStr(body, "message");
    Alert("⛔ [EA] 绑定失败：" + errCode + " - " + errMsg);
    Print("[CT] 失败 status=", status, " code=", errCode, " msg=", errMsg);
    _CT_lastInitError = 2;
    return false;
}

bool _CT_ValidateToken() {
    if (_CT_epValidate == "" || _CT_token == "") return true;
    string body = _CT_HttpGet(_CT_epValidate + "?token=" + _CT_token);
    if (body == "") return _CT_tokenValid;
    bool valid = (StringFind(body, "\"valid\":true") >= 0);
    { string _ex = _CT_JsonStr(body, "expiry"); if (_ex != "") _CT_expiry = _ex; }
    if (_CT_tokenValid && !valid) {
        Print("[CT] ⛔ Token 已失效，停止上报，策略暂停开仓");
        Alert("⛔ Token 已失效，策略将暂停开新仓（持仓保留），请联系管理员");
    } else if (!_CT_tokenValid && valid) {
        Print("[CT] ✅ Token 已恢复，策略恢复");
        Alert("✅ Token 已恢复，策略恢复正常");
    }
    _CT_tokenValid = valid;
    return _CT_tokenValid;
}


//+==================================================================+
//|  [TICKETS] 已上报集合                                              |
//+==================================================================+
bool _CT_ReportedHas(ulong deal) {
    for (int i = 0; i < _CT_reportedCnt; i++) if (_CT_reported[i] == deal) return true;
    return false;
}

void _CT_ReportedAdd(ulong deal) {
    ArrayResize(_CT_reported, _CT_reportedCnt + 1);
    _CT_reported[_CT_reportedCnt++] = deal;
    if (_CT_reportedCnt > 1000) {
        for (int k = 0; k < 500; k++) _CT_reported[k] = _CT_reported[k + 500];
        _CT_reportedCnt = 500;
        ArrayResize(_CT_reported, _CT_reportedCnt);
    }
}


//+==================================================================+
//|  [REPORT] 心跳 / 事件上报                                          |
//+==================================================================+
string _CT_BuildPositionsArray() {
    string arr = "[";
    bool first = true;
    int total = PositionsTotal();
    for (int i = 0; i < total; i++) {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        if (_CT_magic > 0 && PositionGetInteger(POSITION_MAGIC) != _CT_magic) continue;

        long type = PositionGetInteger(POSITION_TYPE);
        if (type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL) continue;

        if (!first) arr += ",";
        first = false;
        string typeStr = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
        double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        arr += "{";
        arr += "\"ticket\":"      + IntegerToString((long)ticket)                          + ",";
        arr += "\"symbol\":\""    + PositionGetString(POSITION_SYMBOL)                     + "\",";
        arr += "\"type\":\""      + typeStr                                                + "\",";
        arr += "\"lot\":"         + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2)  + ",";
        arr += "\"profit\":"      + DoubleToString(pnl, 2)                                 + ",";
        arr += "\"open_price\":"  + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5) + ",";
        arr += "\"sl\":"          + DoubleToString(PositionGetDouble(POSITION_SL), 5)      + ",";
        arr += "\"tp\":"          + DoubleToString(PositionGetDouble(POSITION_TP), 5);
        arr += "}";
    }
    arr += "]";
    return arr;
}

string _CT_BuildJsonBase(string action, string sym, long ticket,
                          double lot, double profit, string result)
{
    double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
    double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
    long   login = (long) AccountInfoInteger(ACCOUNT_LOGIN);
    string srv   = AccountInfoString(ACCOUNT_SERVER);

    string j = "{";
    j += "\"token\":\""         + _CT_token                         + "\",";
    j += "\"login\":\""         + IntegerToString(login)            + "\",";
    j += "\"server\":\""        + srv                               + "\",";
    j += "\"platform\":\"MT5\",";
    j += "\"account_type\":\"master\",";
    j += "\"ea_serial\":\"" + CT_EA_SERIAL + "\",";
    j += "\"action\":\""        + action                            + "\",";
    j += "\"group_id\":\""      + _CT_groupId                       + "\",";
    j += "\"strategy_name\":\"" + _CT_stratName                     + "\",";
    j += "\"positions\":"       + IntegerToString(PositionsTotal()) + ",";
    j += "\"equity\":"          + DoubleToString(eq, 2)             + ",";
    j += "\"balance\":"         + DoubleToString(bal, 2)            + ",";
    j += "\"total_opens\":"     + IntegerToString(_CT_totalOpens)   + ",";
    j += "\"master_symbol\":\"" + sym                              + "\",";
    j += "\"slave_symbol\":\"\",\"trade_type\":\"\",";
    j += "\"master_ticket\":"   + IntegerToString(ticket)          + ",";
    j += "\"slave_ticket\":0,";
    j += "\"lot\":"             + DoubleToString(lot, 2)           + ",";
    j += "\"profit\":"          + DoubleToString(profit, 2)        + ",";
    j += "\"result\":\""        + result                           + "\",";
    j += "\"error_code\":0,\"error_msg\":\"\",";
    j += "\"timestamp\":"       + IntegerToString((long)TimeCurrent());
    return j;
}

void _CT_SendHeartbeat() {
    string j = _CT_BuildJsonBase("heartbeat", "", 0, 0, 0, "success");
    string positions = _CT_BuildPositionsArray();
    StringReplace(j, "\"timestamp\":",
                     "\"positions_detail\":" + positions + ",\"timestamp\":");
    j += "}";
    string body;
    _CT_HttpPostJson(_CT_epHeartbeat, j, body);

    int total = PositionsTotal();
    if (total != _CT_lastPosCount) {
        bool isOpen = (total > _CT_lastPosCount && _CT_lastPosCount >= 0);
        if (isOpen) _CT_totalOpens++;
        _CT_lastPosCount = total;
    }
}

void _CT_ReportTradeClose(ulong deal, string sym, string dir, double lot, double pnl) {
    string j = _CT_BuildJsonBase("trade_close", sym, (long)deal, lot, pnl, "success");
    StringReplace(j, "\"trade_type\":\"\"", "\"trade_type\":\"" + dir + "\"");
    j += "}";
    string body;
    _CT_HttpPostJson(_CT_epHeartbeat, j, body);
}


//+==================================================================+
//|  [SCAN] 扫描历史平仓 deal                                          |
//+==================================================================+
void _CT_ScanClosed() {
    datetime since = TimeCurrent() - 86400;
    if (!HistorySelect(since, TimeCurrent())) return;
    int total = HistoryDealsTotal();
    for (int i = 0; i < total; i++) {
        ulong deal = HistoryDealGetTicket(i);
        if (deal == 0) continue;
        if (HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        if (_CT_magic > 0 && HistoryDealGetInteger(deal, DEAL_MAGIC) != _CT_magic) continue;
        if (_CT_ReportedHas(deal)) continue;

        string sym = HistoryDealGetString(deal, DEAL_SYMBOL);
        double lot = HistoryDealGetDouble(deal, DEAL_VOLUME);
        double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT)
                   + HistoryDealGetDouble(deal, DEAL_SWAP)
                   + HistoryDealGetDouble(deal, DEAL_COMMISSION);
        // OUT deal 的 type 与原仓位方向相反
        long dealType = HistoryDealGetInteger(deal, DEAL_TYPE);
        string dir = (dealType == DEAL_TYPE_BUY) ? "SELL" : "BUY";

        _CT_ReportTradeClose(deal, sym, dir, lot, pnl);
        _CT_ReportedAdd(deal);

        if (_CT_verbose) Print("[CT-SCAN] 上报平仓 deal=", deal, " ", sym,
                                " ", dir, " pnl=", DoubleToString(pnl, 2));
    }
}


//+==================================================================+
//|  [INVITE] 邀请码兑换（第一次启动自动换 token）                      |
//+==================================================================+
string _CT_RedeemInviteCode(string inviteCode, string siteURL, string eaName) {
    long   login  = (long) AccountInfoInteger(ACCOUNT_LOGIN);
    string server = AccountInfoString(ACCOUNT_SERVER);

    string base = siteURL;
    while (StringSubstr(base, StringLen(base) - 1, 1) == "/")
        base = StringSubstr(base, 0, StringLen(base) - 1);
    string endpoint = base + "/wp-json/copytrade/v1/redeem-invite-code";

    string j = "{";
    j += "\"code\":\""     + inviteCode                   + "\",";
    j += "\"login\":\""    + IntegerToString(login)        + "\",";
    j += "\"server\":\""   + server                        + "\",";
    j += "\"platform\":\"MT5\",";
    j += "\"ea_name\":\""  + eaName                        + "\",";
    j += "\"ea_serial\":\"" + CT_EA_SERIAL + "\"";
    j += "}";

    string body;
    int status = _CT_HttpPostJson(endpoint, j, body);
    if (status < 0) {
        Alert("⚠️ [CT] 邀请码兑换失败：无法连接服务器。\n请检查 SiteURL 以及 MT5 网络白名单。");
        _CT_lastInitError = 1;
        return "";
    }
    if (status >= 200 && status < 300 && StringFind(body, "\"ok\":true") >= 0) {
        // 提取 token 字段
        string pat = "\"token\":\"";
        int p = StringFind(body, pat);
        if (p < 0) return "";
        p += StringLen(pat);
        int e = StringFind(body, "\"", p);
        if (e < 0) return "";
        string token = StringSubstr(body, p, e - p);
        Print("[CT] ✅ 邀请码兑换成功，Token 已获取");
        return token;
    }
    // 兑换失败：显示原因
    string pat = "\"message\":\"";
    int p = StringFind(body, pat);
    if (p >= 0) {
        p += StringLen(pat);
        int e = StringFind(body, "\"", p);
        if (e >= 0) {
            Alert("⛔ [CT] 邀请码兑换失败：" + StringSubstr(body, p, e - p));
        }
    }
    _CT_lastInitError = 2;
    return "";
}

//+==================================================================+
//|  [PUBLIC API] 对外接口                                             |
//+==================================================================+

// 扩展版 CT_Init：支持邀请码自动兑换 + GlobalVariable 持久化
// inviteCode  非空时：第一次启动自动兑换 token 并存 GlobalVariable
// token       非空时：直接用（优先级最高）
// 两者都空时：先查 GlobalVariable，还是没有才报错
bool CT_Init(string token, string siteURL,
             int heartbeatSec = 5, int magic = 0, bool verbose = false,
             string inviteCode = "")
{
    _CT_lastInitError = 0;
    if (siteURL == "") {
        Print("[CT] ⚠️ 面板地址为空, 引擎未启动");
        _CT_lastInitError = 2;
        _CT_active = false;
        return false;
    }

    string useToken = token;

    // [invite-only] 仅用授权码: 不读 GlobalVariable / 不读写本地缓存
    //               每次启动向服务器兑换 (服务端幂等: 同账号同序号返回同一 token)
    if (useToken == "" && inviteCode != "") {
        Print("[CT] 检测到授权码, 正在向服务器验证...");
        useToken = _CT_RedeemInviteCode(inviteCode, siteURL, "MasterEA");
    }

    if (useToken == "") {
        _CT_active = false;
        return false;
    }

    _CT_token        = useToken;
    _CT_siteURL      = siteURL;
    _CT_heartbeatSec = MathMax(3, heartbeatSec);
    _CT_magic        = magic;
    _CT_verbose      = verbose;

    string base = siteURL;
    while (StringSubstr(base, StringLen(base) - 1, 1) == "/")
        base = StringSubstr(base, 0, StringLen(base) - 1);
    _CT_epHeartbeat = base + "/wp-json/copytrade/v1/heartbeat";
    _CT_epBind      = base + "/wp-json/copytrade/v1/token/bind";
    _CT_epValidate  = base + "/wp-json/copytrade/v1/validate";

    string tokenHint = "";
    if (StringLen(useToken) > 6)
        tokenHint = StringSubstr(useToken, 0, 4) + "..." + StringSubstr(useToken, StringLen(useToken) - 2, 2);
    Print("════════════════════════════════════════════");
    Print("[EA] 引擎已启用");
    Print("[EA]   面板: ", siteURL);
    Print("[EA]   Token: ", tokenHint);
    Print("[EA]   Magic 过滤: ", magic == 0 ? "无（上报全部持仓）" : IntegerToString(magic));
    Print("[EA] 上报内容: 当前持仓、账户权益/余额、平仓盈亏");
    Print("[EA] 如需关闭, 把 CT_Enabled 改为 false");
    Print("════════════════════════════════════════════");

    if (!_CT_Bind()) {
        _CT_active = false;
        return false;
    }
    _CT_SendHeartbeat();
    _CT_active = true;
    return true;
}

void CT_Tick() {
    if (!_CT_active) return;

    if (_CT_epValidate != "" && (TimeCurrent() - _CT_lastVal) >= 300) {
        _CT_ValidateToken();
        _CT_lastVal = TimeCurrent();
    }
    if (!_CT_tokenValid) return;

    if ((TimeCurrent() - _CT_lastHB) >= _CT_heartbeatSec) {
        _CT_SendHeartbeat();
        _CT_lastHB = TimeCurrent();
    }

    if ((TimeCurrent() - _CT_lastScan) >= 5) {
        _CT_ScanClosed();
        _CT_lastScan = TimeCurrent();
    }
}

// 立即触发心跳。MT5 EA 在 OnTrade() 里调用这个，让从账户在 1 秒内看到新持仓。
void CT_ForceHeartbeat() {
    if (!_CT_active) return;
    _CT_SendHeartbeat();
    _CT_lastHB = TimeCurrent();
}

void CT_Deinit(int reason) {
    bool realStop = (reason == REASON_REMOVE     ||
                     reason == REASON_CHARTCLOSE ||
                     reason == REASON_CLOSE);
    if (realStop && _CT_active) {
        string j = _CT_BuildJsonBase("offline", "", 0, 0, 0, "success");
        j += "}";
        string body;
        _CT_HttpPostJson(_CT_epHeartbeat, j, body);
    }
    _CT_active = false;
}

bool CT_IsActive() {
    return _CT_active && _CT_tokenValid;
}

//+------------------------------------------------------------------+
//|  CT_CanTrade - 策略代码可调用此函数判断是否允许交易                |
//|  返回 false 时：Token 已失效，应跳过开仓逻辑（持仓保留）          |
//+------------------------------------------------------------------+
bool CT_CanTrade() {
    return _CT_tokenValid;
}

// 0=ok, 1=transient (network unreachable), 2=permanent (server rejected)
int CT_GetLastInitError() { return _CT_lastInitError; }

// 授权到期日字符串 YYYY-MM-DD (空 = 永久 / 尚未绑定)
string CT_GetExpiry() { return _CT_expiry; }
//+------------------------------------------------------------------+

//+==================================================================+
//|  [HELPERS] 周末时段 + 全平 + 综合放行                              |
//+==================================================================+

// 北京时间 = GMT + 8 (无夏令时)。周五 23:30 - 周一 08:00 禁止交易。
bool InWeekendCloseWindow()
{
   datetime nowBJ = TimeGMT() + 8 * 3600;
   MqlDateTime t;
   TimeToStruct(nowBJ, t);
   int dow = t.day_of_week;                    // 0=Sun 1=Mon ... 5=Fri 6=Sat
   int hm  = t.hour * 60 + t.min;
   if (dow == 5 && hm >= 23 * 60 + 30) return true;
   if (dow == 6)                       return true;
   if (dow == 0)                       return true;
   if (dow == 1 && hm <  8 * 60)       return true;
   return false;
}

bool TradingAllowed()
{
   if (CT_Enabled && !CT_CanTrade()) return false;
   if (InWeekendCloseWindow())       return false;
   return true;
}

// 平掉本 EA 持仓 + 删除本 EA 挂单。需要 CTrade trade; 全局变量。
void CloseAllStrategyPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if (tk == 0) continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)Magic_Number) continue;
      trade.PositionClose(tk);
   }
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong tk = OrderGetTicket(i);
      if (tk == 0) continue;
      if (OrderGetInteger(ORDER_MAGIC) != (long)Magic_Number) continue;
      trade.OrderDelete(tk);
   }
}


//+==================================================================+
//|  [HUD] 授权到期日图表显示 (MT4/MT5 通用)                           |
//+==================================================================+

// 在图表右上角画一行 label。MT4(build 600+)/MT5 通用 API。
void CT_HudLabel(string name, string text, int ydist, color col)
{
   if (ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  ydist);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetString (0, name, OBJPROP_FONT,       "Consolas");
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
}

// 根据 CT_GetExpiry() 渲染授权到期 HUD。
void CT_DrawHUD()
{
   if (!CT_Enabled || !CT_ShowHUD) return;

   string exp = CT_GetExpiry();
   string l1, l2;
   color  col;

   if (exp == "") {
      l1  = "[" + CT_EA_SERIAL + "] 授权: 有效";
      l2  = "到期: 长期有效";
      col = clrLime;
   } else {
      string dotted = exp;
      StringReplace(dotted, "-", ".");
      datetime et   = StringToTime(dotted);
      long     secs = (long)et + 86399 - (long)TimeCurrent();
      if (secs <= 0) {
         l1  = "[" + CT_EA_SERIAL + "] 授权已过期";
         l2  = "到期: " + exp;
         col = clrRed;
      } else {
         long days = secs / 86400;
         l1  = "[" + CT_EA_SERIAL + "] 授权到期: " + exp;
         l2  = "剩余: " + IntegerToString((int)days) + " 天";
         col = (days <= 7) ? clrOrange : clrLime;
      }
   }
   CT_HudLabel("CTHUD_l1", l1, 20, col);
   CT_HudLabel("CTHUD_l2", l2, 36, col);
   ChartRedraw(0);
}

void CT_RemoveHUD()
{
   ObjectDelete(0, "CTHUD_l1");
   ObjectDelete(0, "CTHUD_l2");
}

//+==================================================================+
//|  [STRATEGY EVENT HANDLERS - wrapped]                              |
//+==================================================================+
int OnInit()
  {
   //--- [LICENSE] 未填授权码则禁止运行 (invite-only: 无 Token 回退)
   if (CT_Enabled && CT_InviteCode == "")
     {
      Alert("请填写授权码后再运行 (格式 XXXX-XXXX-XXXX)");
      Print("[EA] 未填写授权码, EA 不运行");
      return(INIT_FAILED);
     }

   //--- 魔术号过滤
   int ctMagic = (CT_MagicFilter != 0) ? CT_MagicFilter : (int)Magic_Number;

   //--- 启动引擎 (根据失败类型决定是否阻止运行)
   if (CT_Enabled)
     {
      if (!CT_Init("", CT_SITE_URL, CT_HeartbeatSec, ctMagic, false, CT_InviteCode))
        {
         if (CT_GetLastInitError() == 2)
           {
            Alert("授权码无效或已过期, EA 不运行。请检查授权码后重新加载。");
            Print("[EA] 授权码被拒绝, EA 不运行");
            return(INIT_FAILED);
           }
         Print("[EA] 服务暂时不可用 (网络问题?), 策略照常运行");
        }
     }
   EventSetTimer(1);

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
   if (CT_Enabled) CT_Deinit(reason);
   EventKillTimer();
   CT_RemoveHUD();

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
   if (InWeekendCloseWindow()) return;
   if (CT_Enabled && !CT_CanTrade()) return;

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

//+------------------------------------------------------------------+
//| Expert timer function (added by merge_ea.py)                     |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if (CT_Enabled) CT_Tick();
   CT_DrawHUD();
   if (InWeekendCloseWindow())
     {
      CloseAllStrategyPositions();
      return;
     }
   if (CT_Enabled && !CT_CanTrade()) return;
  }



//+------------------------------------------------------------------+
//| Expert trade event (MT5, added by merge_ea.py)                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
   if (CT_Enabled) CT_ForceHeartbeat();
   if (!TradingAllowed()) return;
  }
