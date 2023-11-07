SET DATEFIRST 1;
WITH fr_net AS (		SELECT
								freipr.freight,
								DATEPART(WEEK, freipr.datebeg) 'week',
								AVG(freipr.net) 'avg_net'
						FROM
								freipr
						WHERE
								DATEPART(WEEK, freipr.datebeg) >= DATEPART(WEEK,CAST(GETDATE() AS DATE))
								AND YEAR(freipr.datebeg) = 2023
								AND freipr.net > 0
						GROUP BY
								freipr.freight,
								DATEPART(WEEK, freipr.datebeg)),


stop_freight AS (		SELECT
								s.date,
								s.freight
						FROM
								stopsalefreight s
						WHERE
								s.date > CAST(GETDATE() + 2 AS DATE)),


freight_block AS (		SELECT
								DATEPART(WEEK, frblock.Date) 'week',
								frblock.Date,
								freight.lname 'flight',
								CASE WHEN stop_freight.freight IS NULL THEN 0 ELSE 1 END 'stop_sale',
								(frblock.bcount + frblock.rcount) 'forecast_pax'
						FROM
								frblock
								LEFT JOIN freight			ON freight.inc = frblock.freight
								LEFT JOIN town town_source	ON town_source.inc = freight.source
								LEFT JOIN town town_target	ON town_target.inc = freight.target
								LEFT JOIN stop_freight		ON frblock.freight = stop_freight.freight AND frblock.date = stop_freight.date
						WHERE
								town_source.state IN (210357,325801)
								AND town_target.state = 20613
								AND YEAR(frblock.Date) = 2023
								AND frblock.bcount > 0),

forecast_pax AS (		SELECT
								b.week,
								b.flight,
								SUM(b.forecast_pax) 'forecast_pax'
						FROM
								freight_block b
						WHERE
								b.stop_sale = 0
						GROUP BY
								b.week,
								b.flight),


main_data AS (			SELECT
								town_source.alias 'from',
								town_target.alias 'to',
								DATEPART(WEEK, frblock.Date) 'week',
								freight.lname 'flight',
								forecast_pax.forecast_pax,
								SUM(frblock.bcount) 'block',
								SUM(frblock.rcount) * -1 'sold',
								SUM(frblock.bcount + frblock.rcount) 'left',
								AVG(fr_net.avg_net) 'ow_net'
						FROM
								frblock

								LEFT JOIN freight			ON freight.inc = frblock.freight
								LEFT JOIN town town_source	ON town_source.inc = freight.source
								LEFT JOIN town town_target	ON town_target.inc = freight.target
								LEFT JOIN fr_net			ON fr_net.freight = freight.inc AND fr_net.week = DATEPART(WEEK, frblock.Date)
								LEFT JOIN forecast_pax		ON forecast_pax.flight = freight.lname AND forecast_pax.week = fr_net.week
						WHERE
								town_source.state IN (210357,325801)
								AND town_target.state = 20613
								AND DATEPART(WEEK, frblock.Date) >= DATEPART(WEEK,CAST(GETDATE() AS DATE))
								AND YEAR(frblock.Date) = 2023
								AND frblock.bcount > 0
						GROUP BY
								town_source.alias,
								town_target.alias,
								DATEPART(WEEK, frblock.Date),
								freight.lname,
								forecast_pax.forecast_pax),

add_calc AS (			SELECT
								t.*,
								'|' AS '|',
								(t.sold + 0.0) / t.block 'lf',
								SUBSTRING(t.flight, 1 ,2) 'airline',
								CASE WHEN SUBSTRING(t.flight, 1 ,2) = 'FZ' THEN 0.8 ELSE 1 END 'mat',
								CASE WHEN ((t.sold + 0.0) / t.block) < (CASE WHEN SUBSTRING(t.flight, 1 ,2) = 'FZ' THEN 0.8 ELSE 1 END) THEN 1 ELSE 0 END 'burn_checker',
								(t.block * (CASE WHEN SUBSTRING(t.flight, 1 ,2) = 'FZ' THEN 0.8 ELSE 1 END) - t.sold) * t.ow_net * 1.5 'burning_atm',
								(t.block * (CASE WHEN SUBSTRING(t.flight, 1 ,2) = 'FZ' THEN 0.8 ELSE 1 END) - t.sold) 'left_to_sell' -- УДАЛИТЬ МИНУСА
						FROM
								main_data t)

SELECT
		a.[from],
		a.[to],
		a.[week],
		a.[flight],
		a.[lf],
		a.[mat],
		CASE WHEN a.[left_to_sell] < 0 THEN 0 ELSE a.[left_to_sell] END 'left_to_sell',
		a.[forecast_pax],
		CASE WHEN a.[burning_atm] < 0 THEN 0 ELSE a.[burning_atm] END 'burning_atm'
FROM
		add_calc a

WHERE
		a.airline != 'B2'

ORDER BY
		3,1
