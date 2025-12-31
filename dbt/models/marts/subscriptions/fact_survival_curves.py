import pandas as pd
from lifelines import KaplanMeierFitter

def model(dbt, session):
    """
    Calculates Kaplan-Meier survival curves for monthly and annual subscribers
    and compares them against Piano benchmark retention curves.
    """
    
    # Configure the model
    dbt.config(
        materialized="table",
        packages=["pandas", "lifelines"]  # Ensure lifelines is enabled in your Snowflake Anaconda channel
    )

    # 1. Load Data
    # We use .to_pandas() because lifelines requires pandas DataFrames, not Snowpark DataFrames.
    df = dbt.ref("int_subscriber_survival").to_pandas()
    
    # Load the benchmark data (Assuming 'piano_retention_curves' is loaded as a dbt seed)
    piano_df = dbt.ref("piano_retention_curves").to_pandas()

    # 2. Prepare Piano Benchmark Data (Logic from Cell 4 & 8)
    # Calculate days from months
    piano_df['DAY'] = piano_df['MONTH'] * 30
    
    piano_df_monthly = piano_df[['MONTH', 'MONTHLY_75', 'ANNUAL_75']].copy().set_index('MONTH')
    # Adjust index to days (approximate)
    piano_df_monthly.index = (piano_df_monthly.index) * 30 + 1
    piano_df_monthly.index.name = 'DAYS'

    # Reindex to daily frame using forward fill (Logic from Cell 8)
    max_days = int(piano_df_monthly.index.max())
    daily_index = range(1, max_days + 1)
    piano_df_daily = piano_df_monthly.reindex(daily_index).interpolate(method='linear')

    # 3. Calculate Kaplan-Meier Curves (Logic from Cell 7)
    kmf_monthly = KaplanMeierFitter()
    kmf_annual = KaplanMeierFitter()

    # Filter data
    monthly_mask = df['BILLING_PERIOD'] == '1 month'
    annual_mask = df['BILLING_PERIOD'] == '1 year'

    # Fit monthly cohort
    kmf_monthly.fit(
        df[monthly_mask]['DURATION_DAYS'],
        df[monthly_mask]['CHURN_EVENT'],
        label='ACTUAL_MONTHLY_RETENTION'
    )

    # Fit annual cohort
    kmf_annual.fit(
        df[annual_mask]['DURATION_DAYS'],
        df[annual_mask]['CHURN_EVENT'],
        label='ACTUAL_ANNUAL_RETENTION'
    )

    # 4. Combine and Transform Data (Logic from Cell 9)
    # Merge survival curves into a single DataFrame
    survival_curves = pd.merge(
        kmf_monthly.survival_function_.reset_index(), 
        kmf_annual.survival_function_.reset_index(), 
        on='timeline', 
        how='outer'
    )
    
    # Merge with benchmark data
    survival_curves = pd.merge(
        piano_df_daily, 
        survival_curves, 
        left_index=True, 
        right_on='timeline', 
        how='left'
    )
    
    # Rename columns to match target schema
    survival_curves.rename(columns={
        'MONTHLY_75': 'PIANO_MONTHLY_RETENTION',
        'ANNUAL_75': 'PIANO_ANNUAL_RETENTION',
        'timeline': 'DAYS'
    }, inplace=True)
    
    # Clean up index
    survival_curves = survival_curves.set_index('DAYS').reset_index()
    survival_curves['DAYS'] = survival_curves['DAYS'].fillna(0).astype(int)

    # 5. Reshape / Melt Data (Logic from Cell 10)
    final_df = survival_curves.melt(
        id_vars=['DAYS'],
        value_vars=[
            'ACTUAL_MONTHLY_RETENTION',
            'ACTUAL_ANNUAL_RETENTION',
            'PIANO_MONTHLY_RETENTION',
            'PIANO_ANNUAL_RETENTION'
        ],
        var_name='RETENTION_TYPE',
        value_name='SURVIVAL_PROBABILITY'
    )

    # Extract metadata from the retention type string
    final_df['TERM_ID'] = final_df['RETENTION_TYPE'].str.extract(r'(MONTHLY|ANNUAL)')[0]
    final_df['SOURCE'] = final_df['RETENTION_TYPE'].str.extract(r'^(ACTUAL|PIANO)')[0]
    
    # Map friendly names to IDs
    final_df['TERM_ID'] = final_df['TERM_ID'].replace({
        'MONTHLY': 'TMUO13PYIA2B', 
        'ANNUAL': 'TMFO2DRVWX71'
    })

    # Final cleanup
    final_df = final_df.drop(columns=['RETENTION_TYPE'])
    final_df = final_df[['DAYS', 'TERM_ID', 'SOURCE', 'SURVIVAL_PROBABILITY']]

    # Handle any NaN values that might have been introduced by the outer merge
    final_df = final_df.dropna(subset=['SURVIVAL_PROBABILITY'])

    return final_df
