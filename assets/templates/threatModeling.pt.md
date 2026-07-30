---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Sessão de modelagem de ameaças
language: pt
---

<!-- _class: title -->

# Sessão de modelagem de ameaças
## Sistema · Data · Facilitador · Participantes

---

# Escopo e objetivo

- Qual sistema ou componente estamos modelando hoje?
- O que está explicitamente fora do escopo:…
- Suposições com as quais estamos trabalhando:…
- Resultado: ameaças ponderadas com mitigações e um proprietário

---

<!-- _class: table table-editable -->

# Mapeando o sistema

| Elemento | Tipo | Notas |
| --- | --- | --- |
| … | Componente | … |
| … | Fluxo de dados | … |
| … | Parte externa | … |

---

# Limites de confiança

- Onde os dados passam de confiáveis ​​para não confiáveis?
- Quais limites vemos: rede, processo, usuário, cadeia de suprimentos?
- Onde acontece a autenticação e a validação de entrada?
- Desenhe todos os limites no esboço do sistema:…

---

<!-- _class: table -->

# Referência STRIDE

| Categoria | Significado |
| --- | --- |
| Falsificação | Fingir ser outro usuário ou serviço |
| Adulteração | Modificação não autorizada de dados ou código |
| Repúdio | Negar que uma ação tenha ocorrido |
| Divulgação de informações | Informações que chegam àqueles que não têm permissão para vê-las |
| Negação de serviço | Tornando o sistema inutilizável ou inacessível |
| Elevação de privilégio | Ganhando mais privilégios do que concedidos |

---

<!-- _class: table table-editable -->

# Coletando ameaças

| Ameaça | Categoria PASSADA | Componente | Risco |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Priorizando: probabilidade × impacto

- Probabilidade: quão provável é o abuso (baixa, média, alta)?
- Impacto: quanto dano se acontecer?
- Risco = probabilidade × impacto; alto-alto vai primeiro
- Na dúvida: escolha a estimativa mais alta e observe o porquê

---

<!-- _class: table table-editable -->

# Mitigações e ações

| Mitigação | Proprietário | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# O que aceitamos conscientemente

- Que ameaças não abordamos deliberadamente: …
- Por que isso é justificado (probabilidade, custo, contexto): …
- Quem é o dono desta decisão: Função
- Quando revisitamos isso:…

---

# Sessão concluída
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Escopo e premissas registradas
- [ ] Componentes, fluxos de dados e partes externas mapeadas
- [ ] Limites de confiança traçados
- [ ] Todas as seis categorias STRIDE percorridas
- [ ] Ameaças priorizadas por probabilidade x impacto
- [ ] Mitigações atribuídas a um proprietário
- [ ] Riscos aceitos registrados e possuídos
