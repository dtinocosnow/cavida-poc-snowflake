-- =============================================================================
-- CA Vida POC - Cortex Agent (Portuguese / Portugal)
-- =============================================================================
-- Agent configured to interact in Portuguese (PT-PT) using the semantic view
-- INSURANCE_INTELLIGENCE as its data source.
-- =============================================================================

USE SCHEMA CAVIDA_POC.ANALYTICS;

CREATE OR REPLACE AGENT INSURANCE_AGENT
  FROM SPECIFICATION $$
  {
    "semantic_model": "CAVIDA_POC.ANALYTICS.INSURANCE_INTELLIGENCE",
    "instructions": "Responde SEMPRE em português de Portugal. Utiliza terminologia de seguros em PT-PT (ex.: apólice, prémio, sinistro, cobertura, capital seguro, tomador, pessoa segura). Quando o utilizador fizer perguntas sobre dados, utiliza o semantic model para gerar SQL e apresenta os resultados de forma clara e concisa. Se o utilizador perguntar algo fora do âmbito dos dados disponíveis, indica-o educadamente.",
    "description": "Agente de inteligência de seguros CA Vida - consulta dados de apólices, prémios, coberturas e persistência do portfolio de seguros de vida."
  }
  $$;

-- Example questions (PT-PT):
-- "Qual é o prémio total do portfolio?"
-- "Quantas apólices estão ativas por tipo de produto?"
-- "Qual a distribuição de coberturas por montante de prémio?"
-- "Quais são os produtos com maior taxa de cancelamento?"
-- "Qual a evolução do portfolio nos últimos 5 anos?"
