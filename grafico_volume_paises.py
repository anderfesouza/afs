import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import numpy as np

# --- 1. Dados Completos Extraídos do Relatório ---
dates_str = ['01/12/2024', '02/12/2024', '16/01/2025', '25/01/2025', '23/04/2025',
             '24/06/2025', '19/07/2025', '26/08/2025', '07/10/2025', '05/12/2025']
dates = pd.to_datetime(dates_str, format='%d/%m/%Y')

# Transcrição completa de todas as linhas da imagem
data_full = {
    'Alemanha':    [949, 771, 762, 734, 776, 740, 690, 680, 675, 656],
    'Áustria':     [ 69,  60,  57,  55,  64,  58,  57,  55,  55,  51],
    'Bélgica':     [131, 106, 107, 106, 102,  91,  84,  83,  83,  74],
    'Croácia':     [ 10,  10,  10,  10,   9,   9,   9,   9,   9,  10],
    'Dinamarca':   [ 52,  47,  45,  45,  46,  39,  40,  39,  40,  38],
    'EAU':         [ 10,  10,  10,  10,  10,   9,  10,   9,  10,  11],
    'Espanha':     [382, 303, 292, 291, 325, 305, 288, 286, 277, 272],
    'Estônia':     [  9,   9,   9,   9,   9,   9,   9,   9,   9,  10],
    'EUA e Canadá':[ 43,  34,  35,  34,  32,  30,  23,  30,  29,  30],
    'Finlândia':   [ 26,  23,  22,  22,  21,  19,  19,  20,  23,  24],
    'França':      [288, 231, 216, 216, 232, 218, 205, 206, 204, 202],
    'Holanda':     [158, 126, 120, 118, 122, 111, 101, 100, 100,  97],
    'Hungria':     [ 16,  16,  17,  17,  16,  15,  13,  14,  14,  14],
    'Irlanda':     [392, 322, 352, 347, 384, 349, 333, 325, 323, 300],
    'Itália':      [309, 254, 256, 252, 261, 243, 231, 223, 219, 213],
    'Luxemburgo':  [ 48,  38,  37,  36,  39,  37,  34,  30,  28,  28],
    'Noruega':     [ 39,  32,  34,  34,  35,  31,  32,  29,  31,  32],
    'Polônia':     [ 12,  12,  13,  13,  13,  13,  12,  11,  14,  13],
    'Portugal':    [620, 495, 466, 453, 448, 426, 402, 376, 375, 377],
    'Reino Unido': [571, 465, 455, 451, 498, 475, 453, 449, 447, 421],
    'Suécia':      [ 97,  83,  88,  88,  99,  92,  89,  91,  92,  88],
    'Suíça':       [200, 172, 164, 161, 171, 157, 141, 145, 141, 138],
    # O primeiro valor de Geral está vazio na imagem, usamos np.nan
    'Geral':       [np.nan, 3619, 3567, 3502, 3712, 3477, 3275, 3220, 3198, 3099]
}

# Criando o DataFrame
df = pd.DataFrame(data_full, index=dates)

# Transformando para formato longo (ideal para Plotly)
df_long = df.reset_index().melt(id_vars='index', var_name='País', value_name='Volume')
df_long.rename(columns={'index': 'Data'}, inplace=True)

# --- 2. Criação do Gráfico Moderno ---

# Usando uma paleta de cores maior para acomodar 23 categorias distintas
custom_colors = px.colors.qualitative.Dark24 + px.colors.qualitative.Light24

fig = px.line(df_long,
              x='Data',
              y='Volume',
              color='País',
              title='<b>Flutuação Completa de Volume (Todos os Países + Geral)</b><br><sub>Report de Dez 2024 a Dez 2025</sub>',
              template='plotly_dark',
              color_discrete_sequence=custom_colors
              )

# --- 3. Refinamento do Estilo ---

# Linhas suaves e marcadores
fig.update_traces(mode='lines', line_shape='spline')

# Destaque especial para a linha "Geral"
for trace in fig.data:
    if trace.name == 'Geral':
        trace.line.width = 5
        trace.line.color = '#FFFFFF' # Branco puro
        trace.line.dash = 'dot'
        trace.marker.size = 8
        trace.mode = 'lines+markers' # Adiciona marcadores apenas no Geral para destaque
    else:
        # Deixa as linhas dos países um pouco mais finas para não poluir tanto
        trace.line.width = 1.5

# Ajustes de layout
fig.update_layout(
    hovermode='x unified', # Essencial para comparar tantos dados de uma vez
    legend=dict(
        title=None,
        orientation="v", # Legenda vertical à direita devido à quantidade de itens
        yanchor="top",
        y=1,
        xanchor="left",
        x=1.02,
        font=dict(size=10)
    ),
    xaxis=dict(
        title='Data do Report',
        tickformat='%d/%m/%y',
        showgrid=True,
        gridcolor='rgba(128,128,128,0.1)'
    ),
    yaxis=dict(
        title='Volume',
        showgrid=True,
        gridcolor='rgba(128,128,128,0.1)',
        type='log' # OPÇÃO: Escala logarítmica pode ajudar a visualizar os pequenos junto com os grandes. Remova se preferir linear.
    ),
    margin=dict(r=150), # Margem direita para a legenda
    font=dict(family="Roboto, sans-serif")
)

# Se preferir escala linear (padrão), comente a linha "type='log'" acima.

# Salvar o gráfico como HTML
fig.write_html('/home/user/afs/grafico_volume_paises.html')
print("Gráfico salvo com sucesso em: /home/user/afs/grafico_volume_paises.html")
