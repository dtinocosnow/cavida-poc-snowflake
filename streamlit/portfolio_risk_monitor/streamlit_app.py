import streamlit as st
import pandas as pd
import plotly.express as px
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="CA Vida - Portfolio Risk Monitor",
    page_icon="📊",
    layout="wide"
)

session = get_active_session()

def run_query(query):
    return session.sql(query).to_pandas()

@st.cache_data(ttl=300)
def get_portfolio_kpis():
    return run_query("""
        SELECT 
            COUNT(*) as TOTAL_EXPOSURES,
            COUNT(DISTINCT POLICY_RK) as TOTAL_POLICIES,
            SUM(ANNUAL_PREMIUM_AMT::FLOAT) as TOTAL_PREMIUM,
            AVG(ANNUAL_PREMIUM_AMT::FLOAT) as AVG_PREMIUM,
            SUM(CASH_VALUE::FLOAT) as TOTAL_CASH_VALUE,
            COUNT(DISTINCT CASE WHEN X_POLICY_TERMINATION_DT IS NOT NULL THEN POLICY_RK END) as TERMINATED_POLICIES,
            COUNT(DISTINCT CASE WHEN X_POLICY_TERMINATION_DT IS NOT NULL THEN POLICY_RK END)::FLOAT 
                / NULLIF(COUNT(DISTINCT POLICY_RK), 0) * 100 as LAPSE_RATE_PCT
        FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
    """)

@st.cache_data(ttl=300)
def get_premium_distribution():
    return run_query("""
        SELECT 
            CASE 
                WHEN ANNUAL_PREMIUM_AMT <= 0 THEN '0 - Sem premio'
                WHEN ANNUAL_PREMIUM_AMT <= 1000000 THEN '1 - Ate 10K'
                WHEN ANNUAL_PREMIUM_AMT <= 5000000 THEN '2 - 10K-50K'
                WHEN ANNUAL_PREMIUM_AMT <= 10000000 THEN '3 - 50K-100K'
                WHEN ANNUAL_PREMIUM_AMT <= 50000000 THEN '4 - 100K-500K'
                WHEN ANNUAL_PREMIUM_AMT <= 100000000 THEN '5 - 500K-1M'
                ELSE '6 - >1M'
            END as PREMIUM_BAND,
            COUNT(DISTINCT POLICY_RK) as NUM_POLICIES,
            SUM(ANNUAL_PREMIUM_AMT::FLOAT) as TOTAL_PREMIUM
        FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
        WHERE ANNUAL_PREMIUM_AMT IS NOT NULL
        GROUP BY 1
        ORDER BY 1
    """)

@st.cache_data(ttl=300)
def get_monthly_trend():
    return run_query("""
        SELECT 
            DATE_TRUNC('MONTH', EFFECTIVE_DT) as MONTH,
            COUNT(DISTINCT POLICY_RK) as NEW_POLICIES,
            SUM(ANNUAL_PREMIUM_AMT::FLOAT) as PREMIUM,
            COUNT(DISTINCT CASE WHEN X_POLICY_TERMINATION_DT IS NOT NULL THEN POLICY_RK END) as TERMINATED
        FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
        WHERE EFFECTIVE_DT IS NOT NULL
        AND EFFECTIVE_DT >= '2020-01-01'
        AND EFFECTIVE_DT < '2026-07-01'
        GROUP BY 1
        ORDER BY 1
    """)

@st.cache_data(ttl=300)
def get_coverage_concentration():
    return run_query("""
        SELECT 
            c.COVERAGE_TYPE_CD,
            c.X_COVERAGE_SHORT_DESC as COVERAGE_NAME,
            COUNT(DISTINCT u.POLICY_RK) as NUM_POLICIES,
            SUM(u.ANNUAL_PREMIUM_AMT::FLOAT) as TOTAL_PREMIUM,
            SUM(u.CASH_VALUE::FLOAT) as TOTAL_CASH_VALUE,
            AVG(u.ANNUAL_PREMIUM_AMT::FLOAT) as AVG_PREMIUM
        FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE u
        JOIN CAVIDA_POC.POC_LOOK.COVERAGE c ON u.COVERAGE_RIDER_RK = c.COVERAGE_RK
        GROUP BY 1, 2
        ORDER BY TOTAL_PREMIUM DESC
    """)

@st.cache_data(ttl=300)
def get_premium_outliers():
    return run_query("""
        WITH stats AS (
            SELECT AVG(ANNUAL_PREMIUM_AMT::FLOAT) as AVG_P, STDDEV(ANNUAL_PREMIUM_AMT::FLOAT) as STD_P
            FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
            WHERE ANNUAL_PREMIUM_AMT > 0
        )
        SELECT 
            u.POLICY_RK,
            u.X_POLICY_STATUS_CD as STATUS,
            u.ANNUAL_PREMIUM_AMT::FLOAT as PREMIUM,
            u.CASH_VALUE::FLOAT as CASH_VALUE,
            u.EFFECTIVE_DT,
            u.X_POLICY_TERMINATION_DT as TERMINATION_DT,
            ROUND((u.ANNUAL_PREMIUM_AMT::FLOAT - s.AVG_P) / NULLIF(s.STD_P, 0), 2) as Z_SCORE
        FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE u, stats s
        WHERE u.ANNUAL_PREMIUM_AMT > s.AVG_P + (4 * s.STD_P)
        AND u.ANNUAL_PREMIUM_AMT IS NOT NULL
        ORDER BY u.ANNUAL_PREMIUM_AMT DESC
        LIMIT 50
    """)

@st.cache_data(ttl=300)
def get_lapse_by_year():
    return run_query("""
        SELECT 
            YEAR(X_POLICY_TERMINATION_DT) as TERMINATION_YEAR,
            COUNT(DISTINCT POLICY_RK) as TERMINATED_POLICIES,
            SUM(ANNUAL_PREMIUM_AMT::FLOAT) as LOST_PREMIUM
        FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
        WHERE X_POLICY_TERMINATION_DT IS NOT NULL
        AND YEAR(X_POLICY_TERMINATION_DT) >= 2015
        AND YEAR(X_POLICY_TERMINATION_DT) <= 2026
        GROUP BY 1
        ORDER BY 1
    """)

@st.cache_data(ttl=300)
def get_status_distribution():
    return run_query("""
        SELECT 
            X_POLICY_STATUS_CD as STATUS_CODE,
            COUNT(DISTINCT POLICY_RK) as NUM_POLICIES,
            SUM(ANNUAL_PREMIUM_AMT::FLOAT) as TOTAL_PREMIUM
        FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
        GROUP BY 1
        ORDER BY NUM_POLICIES DESC
    """)

# --- UI ---

st.markdown("""
<style>
    .block-container { padding-top: 1rem; }
    .alert-box {
        background: #FEF2F2;
        border: 1px solid #FECACA;
        border-left: 4px solid #EF4444;
        padding: 12px 16px;
        border-radius: 8px;
        margin: 8px 0;
    }
    .ok-box {
        background: #F0FDF4;
        border: 1px solid #BBF7D0;
        border-left: 4px solid #10B981;
        padding: 12px 16px;
        border-radius: 8px;
        margin: 8px 0;
    }
</style>
""", unsafe_allow_html=True)

st.title("📊 CA Vida — Portfolio Risk Monitor")
st.caption("Monitorização de anomalias, concentração de risco e persistência | Powered by Snowflake Cortex")

# --- KPIs ---
kpis = get_portfolio_kpis()
if not kpis.empty:
    row = kpis.iloc[0]
    
    c1, c2, c3, c4, c5 = st.columns(5)
    with c1:
        st.metric("Apólices", f"{int(row['TOTAL_POLICIES']):,}".replace(",", "."))
    with c2:
        st.metric("Exposições", f"{int(row['TOTAL_EXPOSURES']):,}".replace(",", "."))
    with c3:
        st.metric("Prémio Total", f"€{float(row['TOTAL_PREMIUM'])/1e12:.1f}T")
    with c4:
        st.metric("Anuladas", f"{int(row['TERMINATED_POLICIES']):,}".replace(",", "."))
    with c5:
        lapse = float(row['LAPSE_RATE_PCT']) if row['LAPSE_RATE_PCT'] is not None else 0.0
        st.metric("Taxa de Anulação", f"{lapse:.2f}%", 
                  delta=f"{'ALERTA' if lapse > 15 else 'OK'}", 
                  delta_color="inverse" if lapse > 15 else "normal")

st.divider()

# --- TABS ---
tab1, tab2, tab3, tab4 = st.tabs(["📈 Tendências", "⚠️ Anomalias Prémio", "🎯 Concentração", "📉 Persistência"])

with tab1:
    st.subheader("Evolução Mensal (2020-2026)")
    df_trend = get_monthly_trend()
    if not df_trend.empty:
        df_trend['MONTH'] = pd.to_datetime(df_trend['MONTH'])
        
        col1, col2 = st.columns(2)
        with col1:
            fig = px.line(df_trend, x='MONTH', y='NEW_POLICIES', 
                         title='Novas Apólices por Mês',
                         labels={'NEW_POLICIES': 'Apólices', 'MONTH': ''})
            fig.update_layout(height=350)
            st.plotly_chart(fig, use_container_width=True)
        
        with col2:
            fig2 = px.area(df_trend, x='MONTH', y='PREMIUM',
                          title='Prémio Mensal (Volume)',
                          labels={'PREMIUM': 'Prémio', 'MONTH': ''})
            fig2.update_layout(height=350)
            st.plotly_chart(fig2, use_container_width=True)

with tab2:
    st.subheader("Detecção de Anomalias — Prémios Outlier (Z-score > 4)")
    df_outliers = get_premium_outliers()
    if not df_outliers.empty:
        n_outliers = len(df_outliers)
        
        if n_outliers > 20:
            st.markdown(f'<div class="alert-box"><strong>⚠️ ALERTA:</strong> {n_outliers} apólices com prémio anómalo detectadas (>4 desvios padrão)</div>', unsafe_allow_html=True)
        else:
            st.markdown(f'<div class="ok-box"><strong>✓ OK:</strong> Apenas {n_outliers} apólices com prémio outlier — dentro de limites aceitáveis</div>', unsafe_allow_html=True)
        
        col1, col2 = st.columns([2, 1])
        with col1:
            fig = px.scatter(df_outliers, x='Z_SCORE', y='PREMIUM',
                           color='STATUS', hover_data=['POLICY_RK', 'EFFECTIVE_DT'],
                           title='Mapa de Anomalias (Prémio vs Z-Score)',
                           labels={'PREMIUM': 'Prémio Anual', 'Z_SCORE': 'Z-Score'})
            fig.update_layout(height=400)
            st.plotly_chart(fig, use_container_width=True)
        
        with col2:
            st.markdown("**Top 10 Outliers**")
            display_df = df_outliers[['POLICY_RK', 'STATUS', 'PREMIUM', 'Z_SCORE']].head(10)
            st.dataframe(display_df, use_container_width=True)
    
    st.subheader("Distribuição de Prémios por Faixa")
    df_dist = get_premium_distribution()
    if not df_dist.empty:
        fig = px.bar(df_dist, x='PREMIUM_BAND', y='NUM_POLICIES',
                    title='Número de Apólices por Faixa de Prémio',
                    labels={'NUM_POLICIES': 'Apólices', 'PREMIUM_BAND': 'Faixa'},
                    color='TOTAL_PREMIUM', color_continuous_scale='Blues')
        fig.update_layout(height=350)
        st.plotly_chart(fig, use_container_width=True)

with tab3:
    st.subheader("Concentração por Tipo de Cobertura")
    df_cov = get_coverage_concentration()
    if not df_cov.empty:
        col1, col2 = st.columns(2)
        with col1:
            fig = px.pie(df_cov, values='TOTAL_PREMIUM', names='COVERAGE_TYPE_CD',
                        title='Concentração de Prémio por Cobertura',
                        hole=0.4)
            fig.update_layout(height=400)
            st.plotly_chart(fig, use_container_width=True)
        
        with col2:
            fig2 = px.bar(df_cov, x='COVERAGE_TYPE_CD', y='NUM_POLICIES',
                         color='AVG_PREMIUM', color_continuous_scale='RdYlGn',
                         title='Apólices e Prémio Médio por Cobertura',
                         labels={'NUM_POLICIES': 'Apólices', 'COVERAGE_TYPE_CD': 'Tipo Cobertura'})
            fig2.update_layout(height=400)
            st.plotly_chart(fig2, use_container_width=True)
        
        total_premium = float(df_cov['TOTAL_PREMIUM'].sum())
        df_cov['PCT'] = (df_cov['TOTAL_PREMIUM'].astype(float) / total_premium * 100).round(1)
        top_coverage = df_cov.iloc[0]
        
        if float(top_coverage['PCT']) > 50:
            st.markdown(f'<div class="alert-box"><strong>⚠️ Risco de Concentração:</strong> Cobertura tipo <strong>{top_coverage["COVERAGE_TYPE_CD"]}</strong> concentra <strong>{top_coverage["PCT"]:.1f}%</strong> do prémio total</div>', unsafe_allow_html=True)
        
        st.dataframe(df_cov[['COVERAGE_TYPE_CD', 'COVERAGE_NAME', 'NUM_POLICIES', 'TOTAL_PREMIUM', 'AVG_PREMIUM', 'PCT']], 
                    use_container_width=True)

with tab4:
    st.subheader("Análise de Persistência e Anulações")
    df_lapse = get_lapse_by_year()
    if not df_lapse.empty:
        col1, col2 = st.columns(2)
        with col1:
            fig = px.bar(df_lapse, x='TERMINATION_YEAR', y='TERMINATED_POLICIES',
                        title='Apólices Anuladas por Ano',
                        labels={'TERMINATED_POLICIES': 'Anulações', 'TERMINATION_YEAR': 'Ano'},
                        color='LOST_PREMIUM', color_continuous_scale='Reds')
            fig.update_layout(height=350)
            st.plotly_chart(fig, use_container_width=True)
        
        with col2:
            fig2 = px.line(df_lapse, x='TERMINATION_YEAR', y='LOST_PREMIUM',
                          title='Prémio Perdido por Ano (Trend)',
                          labels={'LOST_PREMIUM': 'Prémio Perdido', 'TERMINATION_YEAR': 'Ano'},
                          markers=True)
            fig2.update_layout(height=350)
            st.plotly_chart(fig2, use_container_width=True)
    
    st.subheader("Distribuição por Estado")
    df_status = get_status_distribution()
    if not df_status.empty:
        col1, col2 = st.columns(2)
        with col1:
            fig = px.pie(df_status, values='NUM_POLICIES', names='STATUS_CODE',
                        title='Apólices por Estado', hole=0.3)
            fig.update_layout(height=350)
            st.plotly_chart(fig, use_container_width=True)
        with col2:
            st.dataframe(df_status, use_container_width=True)

# --- Footer ---
st.divider()
st.caption("CA Vida Portfolio Risk Monitor | Snowflake AI Data Cloud | Dados: 24.168.835 registos de exposição")
