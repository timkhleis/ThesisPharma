# Empirical Strategy  
### After the Acquisition — Stayers' Innovation in Pharma M&A

---

## 1. Research Question

Do acquisitions reduce the patent quantity, citation-weighted quality, and technological focus of target-firm inventors who remain with the acquiring group, relative to comparable inventors not yet exposed to a deal?

---

## 2. Data

### Inherited from Ornaghi & Cassi (2026)

Inventor-level panel built from PatStat/EPO (v. 2017) and Orbis/Zephyr (BvD).  
All upstream cleaning — inventor disambiguation, original-applicant recovery, dynamic pharma group construction — is taken as given.

- 311,358 inventors  
- ~1M inventor × year observations  
- Period: 1988–2015  
- 513 acquisitions  
- 39,708 firms  
- 28,807 groups  

### Own additions

- Built a DuckDB/R analytical overlay pipeline producing:
  - `inventor_year`
  - `inventor_ipc_year`
  - `group_ipc_year`
- Linked OECD Patent Quality Indicators (PQII) via `Appln_ID`, adding:
  - originality  
  - radicalness  
  - claims  
  - composite quality score  

---

## 3. Sample Construction and Target Parameter

- **Treated:**  
  Inventor i filed ≥1 patent for target firm c in the 5 years pre-acquisition  

- **Stayer (D = 1):**  
  Files ≥1 patent for the acquiring group within x post-acquisition years  
  x ∈ {3,5}  

- **Control (not-yet-treated):**  
  Employer will be acquired in cohort g' > g but not yet at time t  

  Preferred over never-treated:
  - Never-treated firms are structurally different  
  - Not-yet-treated firms provide a more credible counterfactual  

- **Target parameter:**  
  ATT for post-acquisition output among stayers  
  Acquirer-side inventors excluded  

---

## 4. Outcomes (Inventor × Year)

- **Patents_it:** count  

- **Citations_it:**  
  Forward citations (5/7-year window)  

- **Quality_it:**  
  OECD PQII composite  
  (novel outcome)  

- **TechDrift_it:**  

$$
\text{TechDrift}_{it} =
\frac{\mathbf{v}_i^{t} \cdot \mathbf{v}_i^{0}}
{\|\mathbf{v}_i^{t}\| \cdot \|\mathbf{v}_i^{0}\|}
$$

Declining values indicate movement into unfamiliar fields.  
Captures human capital misallocation (novel measure).

---

## 5. Identification Strategy

Main estimator: Callaway & Sant’Anna (2021) group-time ATT  

- Implemented via `did` R package  
- est_method = "dr"  
- control_group = "notyettreated"  

### Why not TWFE

Treatment timing differs across cohorts.  
TWFE produces biased estimates under treatment effect heterogeneity.  
CS avoids this via clean cohort comparisons.

### Why not-yet-treated controls

Never-treated firms differ structurally.  
Eventually-treated firms differ only in timing → better counterfactual.

### Doubly robust estimation

Combines:

- IPW (PrePatents, Age, Tenure, Exclusivity, FirmPatentStock)  
- Outcome regression  

Consistent if either model is correctly specified.

### Identifying assumption

Conditional parallel trends  

Validated via:

- Event-study pre-trends  
- Formal tests (Roth 2022)  

---

## 6. Estimating Equations

### Event Study (Dynamic ATT)

$$
Y_{ict} =
\sum_{\tau=-5}^{+5}
\lambda_\tau \cdot \mathbf{1}[t - g_c = \tau]
+ \alpha_i + \xi_{ct} + \varepsilon_{ict}
$$

- α_i: inventor fixed effects  
- ξ_ct: company × year fixed effects  

Pre-treatment coefficients test parallel trends.

---

### Aggregate ATT

$$
Y_{ict} =
\lambda \cdot \text{After}_{ict}
+ \alpha_i + \xi_{ct} + \varepsilon_{ict}
$$

λ < 0 → decline in output after acquisition.

---

## 7. Heterogeneity

| Hyp. | Interaction | Mechanism | Sign |
|------|------------|----------|------|
| H2 | Age × After | Junior inventors harder to evaluate | + |
| H3 | Exclusivity × After | Embedded inventors lose internal support | − |
| H4 | CommonIPC × After | Overlap improves integration | + |
| H5 | Big × After | Large deals trigger restructuring | − |

Interpretation: evaluation and integration frictions drive effects.

---

## 8. Additions

### Deal-level technological similarity (DealSim)

$$
\text{DealSim}_c =
\frac{\mathbf{v}_{target}^{pre} \cdot \mathbf{v}_{acquirer}^{pre}}
{\|\mathbf{v}_{target}^{pre}\| \cdot \|\mathbf{v}_{acquirer}^{pre}\|}
$$

High similarity → more redundancy → worse outcomes.

---

## 9. Robustness

- Stayer window: x ∈ {2,3,5}  
- NormCommonIPC  
- Clustered standard errors (group level)  
- Heckman correction (Age as exclusion restriction)  

---

## 10. Novel Contributions

1. OECD quality outcomes  
2. TechDrift measure  
3. Large-scale CS framework with heterogeneity and selection correction  

