---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Continuidade de negócio / teste de DR
language: pt
---

<!-- _class: title -->

# Continuidade de negócio / teste de DR

---

# Cenário de teste

- Cenário: … (por exemplo, interrupção do data center, ransomware)
- Suposição de antemão:…
- Tipo de teste: mesa/parcial/completo

---

# Objetivos e critérios de sucesso

- Objetivo do teste:…
- Critério de sucesso 1:…
- Critério de sucesso 2:…

---

<!-- _class: table table-editable -->

# Processos críticos

| Processo | Prioridade | Depende de |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Visão geral de RTO/RPO

| Processo ou sistema | RTO | RPO | Conheceu? |
| --- | --- | --- | --- |
| … | … | … | Sim / não |
| … | … | … | … |

---

<!-- _class: timeline -->

# Cronograma de teste

- T+0 :: Início do teste :: Cenário anunciado.
- T+… :: Failover iniciado
- T+… :: Recuperação verificada
- T+… :: Fim do teste

---

<!-- _class: table table-editable -->

# Descobertas

| Encontrando | Gravidade | Componente |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Desvios e bloqueadores

- Desvio do manual:…
- Bloqueador durante o teste:…
- Solução alternativa usada:…

---

# Pontos de melhoria
<!-- ocideck_list_style: checklist -->

- [ ] Atualize o manual no ponto:…
- [ ] Ajustar a configuração técnica:…
- [ ] Programe treinamento ou exercício:…

---

# Capacidade de recuperação passa/não passa
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Processos críticos recuperados dentro do RTO
- [ ] A perda de dados permaneceu dentro do RPO
- [ ] O manual provou ser utilizável
- [ ] Veredicto: capacidade de recuperação demonstrada
