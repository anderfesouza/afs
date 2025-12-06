import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

# --- 1. Extração e Preparação dos Dados (Baseado na imagem) ---
# As datas exatas do cabeçalho
dates_str = ['01/12/2024', '02/12/2024', '16/01/2025', '25/01/2025', '23/04/2025',
             '24/06/2025', '19/07/2025', '26/08/2025', '07/10/2025', '05/12/2025']

# Convertendo strings para objetos de data reais para que o eixo X fique proporcional ao tempo
dates = pd.to_datetime(dates_str, format='%d/%m/%Y')

# Extração dos valores principais dos países com maior volume e do Geral.
# Nota: O primeiro valor de 'Geral' está vazio na imagem, então usamos None.
data = {
    'Alemanha': [949, 771, 762, 734, 776, 740, 690, 680, 675, 656],
    'Espanha':  [382, 303, 292, 291, 325, 305, 288, 286, 277, 272],
    'França':   [288, 231, 216, 216, 232, 218, 205, 206, 204, 202],
    'Irlanda':  [392, 322, 352, 347, 384, 349, 333, 325, 323, 300],
    'Itália':   [309, 254, 256, 252, 261, 243, 231, 223, 219, 213],
    'Portugal': [620, 495, 466, 453, 448, 426, 402, 376, 375, 377],
    'Reino Unido':[571, 465, 455, 451, 498, 475, 453, 449, 447, 421],
    'Geral':    [None, 3619, 3567, 3502, 3712, 3477, 3275, 3220, 3198, 3099]
}

# Criando o DataFrame
df = pd.DataFrame(data, index=dates)

# Transformando para formato longo (ideal para Plotly)
df_long = df.reset_index().melt(id_vars='index', var_name='País', value_name='Volume')
df_long.rename(columns={'index': 'Data'}, inplace=True)

# --- 2. Criação do Gráfico Moderno ---

# Cores personalizadas para um visual moderno
custom_colors = px.colors.qualitative.Plotly

fig = px.line(df_long,
              x='Data',
              y='Volume',
              color='País',
              title='<b>Evolução e Flutuação de Volume por País</b><br><sub>(Dez 2024 a Dez 2025)</sub>',
              template='plotly_dark', # Tema escuro moderno
              color_discrete_sequence=custom_colors
              )

# --- 3. Refinamento do Estilo ---

# Adicionar marcadores (pontos) e suavizar as linhas (spline)
fig.update_traces(mode='lines+markers', line_shape='spline', marker=dict(size=6))

# Destacar a linha "Geral"
# Iteramos sobre as linhas do gráfico para encontrar a "Geral" e modificar seu estilo
for trace in fig.data:
    if trace.name == 'Geral':
        trace.line.width = 4          # Mais grossa
        trace.line.color = 'white'    # Cor branca para destaque no fundo escuro
        trace.line.dash = 'dot'       # Estilo pontilhado
        trace.marker.size = 8         # Marcadores maiores

# Ajustes finais de layout
fig.update_layout(
    hovermode='x unified', # Mostra todos os valores da data ao passar o mouse
    legend=dict(
        orientation="h",   # Legenda horizontal no topo
        yanchor="bottom",
        y=1.02,
        xanchor="right",
        x=1
    ),
    xaxis=dict(
        title='Data do Report',
        tickformat='%d/%m/%y', # Formato da data no eixo
        showgrid=True,
        gridcolor='rgba(128,128,128,0.2)' # Grid sutil
    ),
    yaxis=dict(
        title='Volume Total',
        showgrid=True,
        gridcolor='rgba(128,128,128,0.2)' # Grid sutil
    ),
    font=dict(family="Roboto, sans-serif") # Fonte moderna (se disponível no sistema)
)

# Salvar o gráfico como HTML
fig.write_html('/home/user/afs/grafico_volume_paises.html')
print("Gráfico salvo com sucesso em: /home/user/afs/grafico_volume_paises.html")
