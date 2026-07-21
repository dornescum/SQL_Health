CREATE OR REPLACE VIEW v_client_visit_summary AS
SELECT
  u.id AS client_id,
  u.country,
  v.visit_id,
  v.visit_type,
  v.visit_is_locked,
  ROUND(
    100 * (v.reasons_completed + v.food_preferences_completed + v.family_history_completed +
           v.weight_history_completed + v.bariatric_surgery_completed + v.renal_pathology_completed +
           v.diet_history_completed + v.food_history_completed + v.cardio_pathology_completed +
           v.metabolic_pathology_completed + v.neurological_pathology_completed +
           v.gastro_pathology_completed + v.hepatic_pathology_completed +
           v.urological_pathology_completed + v.dermatologic_pathology_completed +
           v.thyroid_pathology_completed + v.respiratory_pathology_completed +
           v.physical_pathology_completed + v.other_pathology_completed +
           v.fibromialgia_pathology_completed + v.nutritional_completed +
           v.medical_values_completed + v.life_style_completed) / 23,
    1
  ) AS pct_sections_complete,
  dnh.requires_specialist,
  dnh.critical_alert_count
FROM users u
JOIN visits v ON v.client_id = u.id
LEFT JOIN client_payments p ON p.visit_id = v.visit_id
LEFT JOIN diagnostic_notes_history dnh ON dnh.visit_id = v.visit_id
WHERE u.role_id = 6;
