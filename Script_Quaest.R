library("dplyr")
library("magrittr")
library("ggplot2")
library("tidyr")
library("RColorBrewer")

# Pré-processamento - Data Cleaning e análise de inconsistências ---- 
## Leitura do banco
survey <- readxl::read_excel("bd_surveyquaest.xlsx") %>%
  mutate(across(where(is.character), as.factor)) %>%
  mutate(idade = cut(idade, breaks = c(16, 18, 25, 35, 45, 55, Inf), right = FALSE))

## Análise do tipo das variáveis dos bancos -----
str(survey)

## Analisando dados faltantes ----
any(is.na(survey))

# Tabelas de contigência
tab_contg <- function(data = readxl::read_excel("bd_surveyquaest.xlsx") %>%
                        mutate(across(where(is.character), as.factor)) %>%
                        mutate(idade = cut(idade, breaks = c(16, 18, 25, 35, 45, 55, Inf), right = FALSE)),
                      .voto = "voto1",
                      .perfil,
                      showFTotal = TRUE,
                      showPropTotal = TRUE,
                      type = 'abs+prop',
                      digits = 2,
                      margin = 2,
                      order = TRUE) {
  # Silenciando mensagens e isolando efeito colateral global como local ----
  op.sum <- options(dplyr.summarise.inform = .Options$dplyr.summarise.inform)
  on.exit(options(op.sum))
  options(dplyr.summarise.inform = FALSE)
  
  # Criando banco para análise
  table <- tibble(voto = data[[.voto]], perfil = data[[.perfil]])
  # Votos por candidato
  votos_cand <- count(table, voto)
  # Agrupando dados por perfil
  table %<>%
    group_by(perfil, voto, .drop = FALSE) %>%
    summarize(n = n())
  
  # Gerado tabelas por tipo escohido
  if (type == "abs") {
    table %<>%
      spread(perfil, n, drop = FALSE)
  } else if (type == "prop") {
    if (margin == 2) {
      table %<>% mutate(prop = n / sum(n) * 100)
    } else {
      table %<>% ungroup() %>% mutate(prop = n / votos_cand$n * 100)
    }
    table %<>%
      select(perfil, voto, prop) %>%
      spread(perfil, prop, drop = FALSE)
  } else {
    # Função auxiliar para chamar de forma recursiva as tabelas "abs" e "prop"
    tab_aux <- function(type = "abs") {
      tab_contg(
        data = data,
        .voto = .voto,
        .perfil = .perfil,
        type = type,
        showFTotal = FALSE,
        showPropTotal = FALSE,
        digits = NULL,
        margin = margin,
        order = FALSE
      ) %>% ungroup() %>% select(-"voto")
    }
    table_total <- tab_aux()
    table_prop <- tab_aux(type = "prop")
    if (!is.null(digits)) {
      table_prop %<>% format_round(digits)
    }
    table <- cbind(voto = votos_cand$voto,
                   mapply(function(x, y) {
                     paste0(x, " (", y, "%)")
                   },
                   table_total,
                   table_prop,
                   SIMPLIFY = FALSE) %>%
                     data.frame()
    )
    showPropTotal = TRUE
    showFTotal = TRUE
  }
  final_table <- table
  # Insere Total e Total Proporcional
  if (showFTotal) {
    final_table %<>% mutate("Total" = votos_cand$n)
  }
  if (showPropTotal) {
    total_votos <- nrow(survey)
    final_table %<>% mutate("Total Prop" = votos_cand$n / total_votos * 100)
    if (!is.null(digits)) {
      final_table %<>% mutate(format_round(final_table %>% select("Total Prop"), 
                                           digits))
    }
  }
  if (type == "abs+prop") {
    final_table %<>% mutate(Total = paste0(Total, " (", `Total Prop`, "%)")) %>%
      select(-c("Total Prop"))
  }
  # Ordena a tabela
  if (order) {
    final_table %<>% slice(order(votos_cand$n,
                                   decreasing = TRUE))
  }
  # Formata a tabela de acordo com a quantidade de dígitos
  if (is.null(digits)){
    return(final_table)
  } else if(type == "prop") {
    final_table <- format_round(final_table, digits)
  }
  return(final_table)
}

format_round <- function(data, digits) {
  mutate_if(data,
            is.double, 
            function(x) {
              prettyNum(round(x, digits), 
                        nsmall = digits, 
                        decimal.mark = ",")
            })
}

tab_contgn <- function(reduce = FALSE, .perfil, ...) {
  if (length(.perfil) > 1) {
    tabs_perfil <- sapply(.perfil, function(x) tab_contg(.perfil = x, ...), 
                          simplify = FALSE)
  if (reduce) {
      tabs_perfil <- Reduce(function(...) inner_join(..., all = FALSE), tabs_perfil)    }
    tabs_perfil
  } else {
    tab_contg(.perfil = .perfil, ...)
  }
}

# Exemplo de uso da tabela
table_perfil <- tab_contgn(data = survey, .perfil = c("sexo", "aval_gov"), 
                    type = "abs+prop"); table_perfil
# Gráfico ----
survey_plot = survey %>%
  group_by(voto1, .drop = FALSE) %>%
  count(sort = TRUE) %>% ungroup() %>%
  mutate(Porcentagem = n / sum(n) * 100)

# Ordenando votos
survey_plot$voto1 <- with(survey_plot, reorder(voto1, n, median))
n.cand <- nrow(survey_plot)
survey_plot$voto1 <- with(survey_plot, 
                          factor(voto1, 
                                 levels = levels(voto1)[c(n.cand - 2, n.cand - 1, 1:(n.cand-3), n.cand)]))

# Paleta de cores
myColours <- colorRampPalette(brewer.pal(9, "Set1"))(length(unique(survey$voto1)))

ggplot(survey_plot, aes(x = Porcentagem, y = voto1, fill = voto1)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = myColours, guide = FALSE) +
  geom_text(aes(x = Porcentagem, 
                label = scales::percent(Porcentagem, scale = 1, decimal.mark = ",")), 
            hjust = -0.25) +
  theme_bw() +
  xlab("Votos") +
  ylab("") +
  labs(caption = paste("Total de votos =", sum(survey_plot$n))) +
  ggtitle("Intenção de votos por candidato") +
  expand_limits(x = 62) 

# Gráfico de avaliação
aval_gov_voto <- survey %>% group_by(voto1) %>% 
  count(aval_gov, sort = TRUE) %>% ungroup() %>%
  mutate(Porcentagem = n / sum(n) * 100)

# Reordenando avaliação de governo
aval_gov_voto$aval_gov <- with(aval_gov_voto,
                               factor(aval_gov,
                               levels = c("Péssima",
                                          "Ruim",
                                          "Regular negativa",
                                          "Regular positiva",
                                          "Boa",
                                          "Ótima",
                                          "NS/NR")))

# Ordenando voto
aval_gov_voto$voto1 <- with(aval_gov_voto, 
                     factor(voto1, 
                            levels = levels(survey$voto1)[c(16, 15, 3, 5, 4, 6, 12, 11, 9, 8, 14, 2, 10, 13, 1, 7)]))

ggplot(aval_gov_voto, aes(x = Porcentagem, y = voto1, group = voto1, fill = voto1)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = myColours, guide = FALSE) +
  theme_bw() +
  xlab("Votos") +
  ylab("") +
  ggtitle("Intenção de votos por candidato e avaliação do governo") +
  facet_grid(. ~ aval_gov, scales = "free_x") +
  theme(strip.background = element_rect(colour = "black", fill = "white", 
                                        size = 1.5, linetype = "solid"))
