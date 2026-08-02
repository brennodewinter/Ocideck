---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Visão geral do processo SIPOC
language: pt
---

<!-- _class: title -->

# Visão geral do processo SIPOC
## Fornecedor · Entrada · Processo · Saída · Cliente

---

<!-- skip -->

# É assim que você trabalha com este modelo

- Use o SIPOC para compreender o escopo e as dependências de um processo, não para registrar todas as ações.
- Use a ajuda e a linha de exemplo como lista de verificação; insira suas respostas em **Limites do processo** e na matriz **SIPOC** vazia.
- De preferência, trabalhe do cliente para o fornecedor, com substantivos para entrada e saída e verbos para etapas do processo.
- Somente os slides rotulados como **Ignorados** serão deixados de fora da apresentação e da exportação. Ative ou desative **Pular** para explicações que seu público pode ou não precisar.

---

# O que o SIPOC mapeia?

- **Fornecedor:** fornece as informações ou recursos que o processo precisa.
- **Entrada:** dados, materiais ou outras condições exigidas pelo processo.
- **Processo:** 4 a 7 atividades de alto nível que transformam a entrada.
- **Saída:** o produto, serviço ou informação que o processo produz.
- **Cliente:** o destinatário interno ou externo da saída.

---

<!-- _class: table table-editable -->

# Defina os limites do processo

| Limite | Valor |
| --- | --- |
| Nome do processo |  |
| Ponto inicial |  |
| Ponto final |  |

---

<!-- skip -->

# Lista de verificação — Quando os limites são suficientemente claros?

- **Processo:** dê um nome reconhecível com verbo e sujeito, por exemplo “Registrar pedido”.
- **Ponto de partida:** Nomeie um evento observável, por exemplo “Solicitação recebida”.
- **Endpoint:** nomeie um resultado demonstrável, por exemplo “Confirmação do pedido enviado”.
- Escolha limites em torno dos quais a equipe possa fazer acordos significativos.
- Mova exceções e processos adjacentes para fora da matriz; anote-os separadamente.

---

<!-- skip -->

# Lista de verificação - Preencher da direita para a esquerda

1. Defina pontos de início e fim claros para o processo.
2. Nomeie os clientes que dependem do resultado.
3. Descreva os resultados que eles recebem.
4. Resuma o processo em 4 a 7 atividades de alto nível.
5. Determine quais insumos essas atividades precisam.
6. Vincule cada insumo ao fornecedor que o disponibiliza.

---

<!-- skip -->
<!-- _class: table -->

# Lista de verificação — Exemplo de uma linha conectada

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Oferta | Solicitação aprovada | Verifique o pedido → registre-se → confirme | Confirmação do pedido | Requerente |

- Leia a linha como uma cadeia: o fornecedor fornece a entrada, o processo a transforma em saída para o cliente.
- Adicione uma nova linha apenas se a cadeia for significativamente diferente.
- Verifique com os envolvidos se não falta nenhum fornecedor, insumo, saída ou cliente importante.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: table table-editable -->

# SIPOC ou um fluxograma detalhado?

| Característica | SIPOC | Fluxograma detalhado |
| --- | --- | --- |
| Propósito | Defina escopo e relacionamentos | Documente o trabalho e as decisões |
| Detalhe | 4 a 7 atividades de alto nível | Pode conter dezenas de etapas |
| Foco | Fornecedores, entradas, saídas e clientes | Sequência, transferências e pontos de decisão |
| Usar | Início de um esforço de melhoria | Execução e análise de falhas |
