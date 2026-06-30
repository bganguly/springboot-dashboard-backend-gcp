module.exports=[63021,(t,e,a)=>{e.exports=t.x("@prisma/client-2c3a283f134fdcb6",()=>require("@prisma/client-2c3a283f134fdcb6"))},28228,75931,56372,55836,34351,59567,98325,t=>{"use strict";t.s(["buildFilterConditions",()=>B,"createOrder",()=>te,"escapeLike",()=>L,"getNotesHaveMatches",()=>v,"getTextProbe",()=>F,"getTokenProbe",()=>U,"listOrders",()=>G,"normalizeStatusList",()=>J,"resolveFilters",()=>x,"todayDateString",()=>b],55836);var e=t.i(63021);let a=globalThis.prisma??new e.PrismaClient({log:["error"]}),r={BAD_REQUEST:400,VALIDATION:422,NOT_FOUND:404,CONFLICT:409,DB_ERROR:500,INTERNAL:500};class o extends Error{code;status;details;constructor(t,e,a){super(e),this.name="AppError",this.code=t,this.status=r[t],this.details=a}}function s(t,a){if(t instanceof o)throw t;if(t instanceof e.Prisma.PrismaClientKnownRequestError)switch(t.code){case"P2002":throw new o("CONFLICT",`${a}: unique constraint violation`,{fields:t.meta?.target});case"P2025":throw new o("NOT_FOUND",`${a}: record not found`);case"P2003":throw new o("BAD_REQUEST",`${a}: foreign key constraint failed`,{field:t.meta?.field_name});default:throw new o("DB_ERROR",`${a}: database error (${t.code})`)}if(t instanceof e.Prisma.PrismaClientValidationError)throw new o("VALIDATION",`${a}: invalid query`);throw new o("INTERNAL",`${a}: unexpected error`,{cause:t instanceof Error?t.message:String(t)})}t.s(["AppError",0,o,"isAppError",0,function(t){return t instanceof o},"mapDbError",0,s],75931),t.s(["getDailyAggregates",()=>n,"updateDailyCustomerCategorySummary",()=>p,"updateDailyCustomerTokenCategoryRollup",()=>f,"updateDailyCustomerTokenCategorySummary",()=>T,"updateDailyCustomerTokenOrderSummary",()=>C,"updateDailyFilterCategorySummary",()=>$,"updateDailyStatusCategorySummary",()=>_,"updateDailySummary",()=>S,"updateOrderCategoryFacts",()=>A],56372);let i="Others";function d(t){return t?t.split(",").map(t=>t.trim()).filter(Boolean):[]}async function n(t){let e={...t,to:t.to||(t.from?b():t.to)};if(!e.from||!e.to)throw new o("BAD_REQUEST","from and to dates are required (YYYY-MM-DD)");let a=null!=e.topCategories&&e.topCategories>0?Math.trunc(e.topCategories):5;try{let t,r,o,s,d=(t=!e.q||""===e.q.trim(),r=!e.status||""===e.status.trim(),o=null==e.minTotal,s=null==e.maxTotal,t&&r&&o&&s)?await R(e):await m(e)??(await l(e)?[]:null)??await c(e)??await I(e)??await g(e)??await O(e)??await N(e);return function(t,e){let a=new Map;for(let e of t){let t=a.get(e.day);t||(t={date:e.day,categories:{},totals:{totalOrders:0,totalRevenue:0,totalItems:0}},a.set(e.day,t));let r=Number(e.total_orders),o=Number(e.total_revenue??0),s=Number(e.total_items),i=t.categories[e.category],d=i?{totalOrders:i.totalOrders+r,totalRevenue:i.totalRevenue+o,totalItems:i.totalItems+s,avgOrderValue:0}:{totalOrders:r,totalRevenue:o,totalItems:s,avgOrderValue:0};d.avgOrderValue=d.totalOrders>0?d.totalRevenue/d.totalOrders:0,t.categories[e.category]=d,t.totals.totalOrders+=r,t.totals.totalRevenue+=o,t.totals.totalItems+=s}return Array.from(a.values()).map(t=>(function(t,e){let a=Object.entries(t.categories);if(a.length<=e)return t;let r=t.categories[i],o=a.filter(([t])=>t!==i).sort(([,t],[,e])=>e.totalRevenue-t.totalRevenue),s=o.slice(0,e),d=o.slice(e).reduce((t,[,e])=>({totalOrders:t.totalOrders+e.totalOrders,totalRevenue:t.totalRevenue+e.totalRevenue,totalItems:t.totalItems+e.totalItems,avgOrderValue:0}),r??{totalOrders:0,totalRevenue:0,totalItems:0,avgOrderValue:0});d.avgOrderValue=d.totalOrders>0?d.totalRevenue/d.totalOrders:0;let n=Object.fromEntries(s);return(d.totalOrders>0||r)&&(n[i]=d),{...t,categories:n}})(t,e))}(d,a)}catch(t){s(t,"getDailyAggregates")}}async function l(t){let e=t.q?.trim();if(!e)return!1;let a=await F(e);return 0===a.customerRows.length&&!a.notesHaveMatches}async function c(t){let r=t.q?.trim();if(!r||null!=t.minTotal||null!=t.maxTotal)return null;let o=/^\d+$/.test(r)?{pattern:`%${L(r)}%`,customerRows:[],notesHaveMatches:await v(r)}:await F(r);if(o.customerRows.length>0||!o.notesHaveMatches)return null;let s=B(await x(t)),i=s.length?e.Prisma.sql`AND ${e.Prisma.join(s," AND ")}`:e.Prisma.empty;return a.$queryRaw(e.Prisma.sql`
    WITH matching_orders AS MATERIALIZED (
      SELECT o.id
      FROM orders o
      WHERE o.notes ILIKE ${o.pattern}
      ${i}
    )
    SELECT
      to_char(f.date, 'YYYY-MM-DD')           AS day,
      f."categoryName"                        AS category,
      count(*)::bigint                        AS total_orders,
      coalesce(sum(f."totalItems"), 0)::bigint AS total_items,
      coalesce(sum(f."totalRevenue"), 0)       AS total_revenue
    FROM matching_orders mo
    JOIN order_category_facts f ON f."orderId" = mo.id
    GROUP BY day, f."categoryName"
    ORDER BY day ASC, f."categoryName" ASC`)}async function m(t){var r;let o;if(null!=t.minTotal||null!=t.maxTotal)return null;let s=(r=t.q,(o=r?.trim().toLowerCase())&&/^[a-z0-9._@-]+$/.test(o)?o:null);if(!s||!(await U(s)).tokenOrderReady)return null;let i=J(t.status),n=d(t.regionCode);if(0===i.length&&0===n.length){let e=await y(t,s);if(e)return e}let l=await a.$queryRaw(e.Prisma.sql`
    SELECT EXISTS (
      SELECT 1
      FROM daily_customer_token_category_summary
      WHERE token = ${s}
      LIMIT 1
    ) AS ready`);if(!l[0]?.ready)return E(t,s,i,n);let c=[e.Prisma.sql`ds.token = ${s}`,e.Prisma.sql`ds.date >= ${t.from}::date`,e.Prisma.sql`ds.date <= ${t.to}::date`];i.length&&c.push(e.Prisma.sql`ds.status = ANY(${i}::text[]::"OrderStatus"[])`),n.length&&c.push(e.Prisma.sql`ds."regionCode" = ANY(${n})`);let m=e.Prisma.sql`WHERE ${e.Prisma.join(c," AND ")}`,I=await a.$queryRaw(e.Prisma.sql`
    SELECT
      to_char(ds.date, 'YYYY-MM-DD') AS day,
      ds."categoryName"              AS category,
      SUM(ds."totalOrders")::bigint  AS total_orders,
      SUM(ds."totalItems")::bigint   AS total_items,
      SUM(ds."totalRevenue")         AS total_revenue
    FROM daily_customer_token_category_summary ds
    ${m}
    GROUP BY ds.date, ds."categoryName"
    ORDER BY ds.date ASC, ds."categoryName" ASC`);return I.length>0?I:await u(t,s,i,n)?E(t,s,i,n):[]}async function u(t,r,o,s){let i=[e.Prisma.sql`ds.token = ${r}`,e.Prisma.sql`ds.date >= ${t.from}::date`,e.Prisma.sql`ds.date <= ${t.to}::date`];o.length&&i.push(e.Prisma.sql`ds.status = ANY(${o}::text[]::"OrderStatus"[])`),s.length&&i.push(e.Prisma.sql`ds."regionCode" = ANY(${s})`);let d=await a.$queryRaw(e.Prisma.sql`
    SELECT EXISTS (
      SELECT 1
      FROM daily_customer_token_order_summary ds
      WHERE ${e.Prisma.join(i," AND ")}
      LIMIT 1
    ) AS has_matches`);return!!d[0]?.has_matches}async function E(t,r,o,s){let i=[e.Prisma.sql`date >= ${t.from}::date`,e.Prisma.sql`date <= ${t.to}::date`];o.length&&i.push(e.Prisma.sql`status = ANY(${o}::text[]::"OrderStatus"[])`),s.length&&i.push(e.Prisma.sql`"regionCode" = ANY(${s})`);let d=e.Prisma.sql`WHERE ${e.Prisma.join(i," AND ")}`,n=await a.$queryRaw(e.Prisma.sql`
    WITH filtered AS MATERIALIZED (
      SELECT date, "customerId", "categoryName", "totalOrders", "totalItems", "totalRevenue"
      FROM daily_customer_category_summary
      ${d}
    ),
    grouped AS (
      SELECT
        f.date                         AS date,
        f."categoryName"               AS category,
        SUM(f."totalOrders")::bigint   AS total_orders,
        SUM(f."totalItems")::bigint    AS total_items,
        SUM(f."totalRevenue")          AS total_revenue
      FROM filtered f
      JOIN customers c ON c.id = f."customerId"
      WHERE lower(c."firstName") = ${r}
         OR lower(c."lastName") = ${r}
      GROUP BY f.date, f."categoryName"
    )
    SELECT
      to_char(date, 'YYYY-MM-DD') AS day,
      category,
      total_orders,
      total_items,
      total_revenue
    FROM grouped
    ORDER BY date ASC, category ASC`);if(!await v(r))return n.length?n:null;let l=B(await x(t)),c=l.length?e.Prisma.sql`AND ${e.Prisma.join(l," AND ")}`:e.Prisma.empty,m=[...n,...await a.$queryRaw(e.Prisma.sql`
    WITH matching_orders AS MATERIALIZED (
      SELECT o.id
      FROM orders o
      JOIN customers c ON c.id = o."customerId"
      WHERE o.notes ILIKE ${`%${L(r)}%`}
        AND NOT (
          lower(c."firstName") = ${r}
          OR lower(c."lastName") = ${r}
        )
        ${c}
    )
    SELECT
      to_char(f.date, 'YYYY-MM-DD')           AS day,
      f."categoryName"                        AS category,
      count(*)::bigint                        AS total_orders,
      coalesce(sum(f."totalItems"), 0)::bigint AS total_items,
      coalesce(sum(f."totalRevenue"), 0)       AS total_revenue
    FROM matching_orders mo
    JOIN order_category_facts f ON f."orderId" = mo.id
    GROUP BY day, f."categoryName"`)];return m.length?m:null}async function y(t,r){let o=null!=t.topCategories&&t.topCategories>0?Math.trunc(t.topCategories):5,[s,d]=await Promise.all([v(r),a.$queryRaw(e.Prisma.sql`
    WITH grouped AS (
      SELECT
        ds.date                       AS date,
        ds."categoryName"             AS category,
        SUM(ds."totalOrders")::bigint AS total_orders,
        SUM(ds."totalItems")::bigint  AS total_items,
        SUM(ds."totalRevenue")        AS total_revenue
      FROM daily_customer_token_category_rollup ds
      WHERE ds.token = ${r}
        AND ds.date >= ${t.from}::date
        AND ds.date <= ${t.to}::date
      GROUP BY ds.date, ds."categoryName"
    ),
    ranked AS (
      SELECT
        *,
        row_number() OVER (
          PARTITION BY date
          ORDER BY total_revenue DESC, category ASC
        ) AS rn
      FROM grouped
    ),
    bucketed AS (
      SELECT
        date,
        CASE WHEN rn <= ${o} THEN category ELSE ${i} END AS category,
        total_orders,
        total_items,
        total_revenue
      FROM ranked
    )
    SELECT
      to_char(date, 'YYYY-MM-DD') AS day,
      category,
      SUM(total_orders)::bigint   AS total_orders,
      SUM(total_items)::bigint    AS total_items,
      SUM(total_revenue)          AS total_revenue
    FROM bucketed
    GROUP BY date, category
    ORDER BY date ASC, category ASC`)]);return 0===d.length?null:s?[...d,...await a.$queryRaw(e.Prisma.sql`
    WITH matching_orders AS MATERIALIZED (
      SELECT o.id
      FROM orders o
      JOIN customers c ON c.id = o."customerId"
      WHERE o.notes ILIKE ${`%${L(r)}%`}
        AND NOT (
          lower(c."firstName") = ${r}
          OR lower(c."lastName") = ${r}
        )
        AND o."placedAt" >= ${t.from}::date
        AND o."placedAt" < (${t.to}::date + interval '1 day')
    )
    SELECT
      to_char(f.date, 'YYYY-MM-DD')           AS day,
      f."categoryName"                        AS category,
      count(*)::bigint                        AS total_orders,
      coalesce(sum(f."totalItems"), 0)::bigint AS total_items,
      coalesce(sum(f."totalRevenue"), 0)       AS total_revenue
    FROM matching_orders mo
    JOIN order_category_facts f ON f."orderId" = mo.id
    GROUP BY day, f."categoryName"`)]:d}async function I(t){let r=t.q?.trim();if(!r||null!=t.minTotal||null!=t.maxTotal)return null;let o=await F(r);if(o.notesHaveMatches)return null;let s=o.customerRows.length>5e3?await a.$queryRaw(e.Prisma.sql`
          SELECT id FROM customers
          WHERE ("firstName" || ' ' || "lastName") ILIKE ${o.pattern}
          LIMIT ${50001}`):o.customerRows;if(0===s.length||s.length>5e4)return null;let i=s.map(t=>t.id),n=J(t.status),l=d(t.regionCode),c=[e.Prisma.sql`ds.date >= ${t.from}::date`,e.Prisma.sql`ds.date <= ${t.to}::date`,e.Prisma.sql`ds."customerId" = ANY(${i})`];n.length&&c.push(e.Prisma.sql`ds.status = ANY(${n}::text[]::"OrderStatus"[])`),l.length&&c.push(e.Prisma.sql`ds."regionCode" = ANY(${l})`);let m=e.Prisma.sql`WHERE ${e.Prisma.join(c," AND ")}`;return a.$queryRaw(e.Prisma.sql`
    SELECT
      to_char(ds.date, 'YYYY-MM-DD') AS day,
      ds."categoryName"              AS category,
      SUM(ds."totalOrders")::bigint  AS total_orders,
      SUM(ds."totalItems")::bigint   AS total_items,
      SUM(ds."totalRevenue")         AS total_revenue
    FROM daily_customer_category_summary ds
    ${m}
    GROUP BY ds.date, ds."categoryName"
    ORDER BY ds.date ASC, ds."categoryName" ASC`)}async function g(t){if(!(!t.q||""===t.q.trim())||null!=t.minTotal||null!=t.maxTotal)return null;let r=J(t.status);if(0===r.length)return null;let o=d(t.regionCode);if(0===o.length)return a.$queryRaw(e.Prisma.sql`
      SELECT
        to_char(ds.date, 'YYYY-MM-DD') AS day,
        ds."categoryName"              AS category,
        SUM(ds."totalOrders")::bigint  AS total_orders,
        SUM(ds."totalItems")::bigint   AS total_items,
        SUM(ds."totalRevenue")         AS total_revenue
      FROM daily_status_category_summary ds
      WHERE ds.date >= ${t.from}::date
        AND ds.date <= ${t.to}::date
        AND ds.status = ANY(${r}::text[]::"OrderStatus"[])
      GROUP BY ds.date, ds."categoryName"
      ORDER BY ds.date ASC, ds."categoryName" ASC`);let s=[e.Prisma.sql`ds.date >= ${t.from}::date`,e.Prisma.sql`ds.date <= ${t.to}::date`,e.Prisma.sql`ds.status = ANY(${r}::text[]::"OrderStatus"[])`];o.length&&s.push(e.Prisma.sql`ds."regionCode" = ANY(${o})`);let i=e.Prisma.sql`WHERE ${e.Prisma.join(s," AND ")}`;return a.$queryRaw(e.Prisma.sql`
    SELECT
      to_char(ds.date, 'YYYY-MM-DD') AS day,
      ds."categoryName"              AS category,
      SUM(ds."totalOrders")::bigint  AS total_orders,
      SUM(ds."totalItems")::bigint   AS total_items,
      SUM(ds."totalRevenue")         AS total_revenue
    FROM daily_filter_category_summary ds
    ${i}
    GROUP BY ds.date, ds."categoryName"
    ORDER BY ds.date ASC, ds."categoryName" ASC`)}async function O(t){if(!(!t.q||""===t.q.trim())||null==t.minTotal&&null==t.maxTotal)return null;let r=J(t.status),o=d(t.regionCode),s=[e.Prisma.sql`f.date >= ${t.from}::date`,e.Prisma.sql`f.date <= ${t.to}::date`];r.length&&s.push(e.Prisma.sql`f.status = ANY(${r}::text[]::"OrderStatus"[])`),o.length&&s.push(e.Prisma.sql`f."regionCode" = ANY(${o})`),null!=t.minTotal&&s.push(e.Prisma.sql`f."orderTotal" >= ${t.minTotal}`),null!=t.maxTotal&&s.push(e.Prisma.sql`f."orderTotal" <= ${t.maxTotal}`);let i=e.Prisma.sql`WHERE ${e.Prisma.join(s," AND ")}`;return a.$queryRaw(e.Prisma.sql`
    SELECT
      to_char(f.date, 'YYYY-MM-DD')           AS day,
      f."categoryName"                        AS category,
      count(*)::bigint                        AS total_orders,
      coalesce(sum(f."totalItems"), 0)::bigint AS total_items,
      coalesce(sum(f."totalRevenue"), 0)       AS total_revenue
    FROM order_category_facts f
    ${i}
    GROUP BY f.date, f."categoryName"
    ORDER BY f.date ASC, f."categoryName" ASC`)}async function R(t){let r=[e.Prisma.sql`ds.date >= ${t.from}::date`,e.Prisma.sql`ds.date <= ${t.to}::date`];if(t.regionCode){let a=t.regionCode.split(",").map(t=>t.trim()).filter(t=>t.length>0);a.length&&r.push(e.Prisma.sql`ds."regionCode" = ANY(${a})`)}let o=e.Prisma.sql`WHERE ${e.Prisma.join(r," AND ")}`;return a.$queryRaw(e.Prisma.sql`
    SELECT
      to_char(ds.date, 'YYYY-MM-DD')    AS day,
      ds."categoryName"                  AS category,
      SUM(ds."totalOrders")::bigint      AS total_orders,
      SUM(ds."totalItems")::bigint       AS total_items,
      SUM(ds."totalRevenue")             AS total_revenue
    FROM daily_summary ds
    ${o}
    GROUP BY ds.date, ds."categoryName"
    ORDER BY ds.date ASC, ds."categoryName" ASC`)}async function N(t){let r,o=B(await x(t)),s=o.length?e.Prisma.sql`WHERE ${e.Prisma.join(o," AND ")}`:e.Prisma.empty,i=o.length?e.Prisma.sql`AND ${e.Prisma.join(o," AND ")}`:e.Prisma.empty,d=t.q?.trim();if(d){let t=`%${L(d)}%`,o=await a.$queryRaw(e.Prisma.sql`
      SELECT id FROM customers
      WHERE ("firstName" || ' ' || "lastName") ILIKE ${t}
      LIMIT ${50001}`);if(o.length>5e4)r=e.Prisma.sql`
        SELECT o.id, o."placedAt"
        FROM orders o
        JOIN customers c ON c.id = o."customerId"
        WHERE ((c."firstName" || ' ' || c."lastName") ILIKE ${t}
          OR o.notes ILIKE ${t})
        ${i}`;else{let a=o.map(t=>t.id),s=a.length?e.Prisma.sql`
            SELECT o.id, o."placedAt"
            FROM unnest(${a}::int[]) AS matched_customer(id)
            JOIN LATERAL (
              SELECT o.id, o."placedAt"
              FROM orders o
              WHERE o."customerId" = matched_customer.id
              ${i}
            ) o ON true`:e.Prisma.sql`SELECT id, "placedAt" FROM orders WHERE false`,n=a.length>5e3;r=d.length>=3&&!n?e.Prisma.sql`
              ${s}
              UNION
              SELECT o.id, o."placedAt"
              FROM orders o
              WHERE o.notes ILIKE ${t}
              ${i}`:s}}else r=e.Prisma.sql`
      SELECT o.id, o."placedAt"
      FROM orders o
      ${s}`;return a.$queryRaw(e.Prisma.sql`
    WITH matching_orders AS MATERIALIZED (
      ${r}
    )
    SELECT
      to_char(mo."placedAt", 'YYYY-MM-DD')                               AS day,
      cat.name                                                           AS category,
      count(DISTINCT mo.id)::bigint                                      AS total_orders,
      coalesce(sum(oi.quantity), 0)::bigint                              AS total_items,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0) AS total_revenue
    FROM matching_orders mo
    JOIN order_items oi ON oi."orderId" = mo.id
    JOIN products p     ON p.id = oi."productId"
    JOIN categories cat ON cat.id = p."categoryId"
    GROUP BY day, cat.name
    ORDER BY day ASC, cat.name ASC`)}async function S(t){await a.$executeRaw(e.Prisma.sql`
    INSERT INTO daily_summary (date, "categoryId", "categoryName", "regionId", "regionCode",
                               "totalOrders", "totalRevenue", "totalItems", "avgOrderValue",
                               "createdAt", "updatedAt")
    SELECT
      o."placedAt"::date,
      cat.id,
      cat.name,
      o."regionId",
      r.code,
      1,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0),
      coalesce(sum(oi.quantity), 0)::int,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0),
      now(),
      now()
    FROM orders o
    JOIN order_items oi ON oi."orderId" = o.id
    JOIN products p     ON p.id = oi."productId"
    JOIN categories cat ON cat.id = p."categoryId"
    JOIN regions r      ON r.id = o."regionId"
    WHERE o.id = ${t}
    GROUP BY o."placedAt"::date, cat.id, cat.name, o."regionId", r.code
    ON CONFLICT (date, "categoryId", "regionId")
    DO UPDATE SET
      "totalOrders"  = daily_summary."totalOrders" + 1,
      "totalRevenue" = daily_summary."totalRevenue" + EXCLUDED."totalRevenue",
      "totalItems"   = daily_summary."totalItems" + EXCLUDED."totalItems",
      "avgOrderValue"= (daily_summary."totalRevenue" + EXCLUDED."totalRevenue")
                       / (daily_summary."totalOrders" + 1),
      "updatedAt"    = now()`)}async function A(t){await a.$executeRaw(e.Prisma.sql`
    INSERT INTO order_category_facts (
      "orderId", "placedAt", date, "regionId", "regionCode", status, "orderTotal",
      "categoryId", "categoryName", "totalItems", "totalRevenue"
    )
    SELECT
      o.id,
      o."placedAt",
      o."placedAt"::date,
      o."regionId",
      r.code,
      o.status,
      o.total,
      cat.id,
      cat.name,
      coalesce(sum(oi.quantity), 0)::int,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0)
    FROM orders o
    JOIN order_items oi ON oi."orderId" = o.id
    JOIN products p     ON p.id = oi."productId"
    JOIN categories cat ON cat.id = p."categoryId"
    JOIN regions r      ON r.id = o."regionId"
    WHERE o.id = ${t}
    GROUP BY o.id, o."placedAt", o."regionId", r.code, o.status, o.total, cat.id, cat.name
    ON CONFLICT ("orderId", "categoryId")
    DO UPDATE SET
      "placedAt" = EXCLUDED."placedAt",
      date = EXCLUDED.date,
      "regionId" = EXCLUDED."regionId",
      "regionCode" = EXCLUDED."regionCode",
      status = EXCLUDED.status,
      "orderTotal" = EXCLUDED."orderTotal",
      "categoryName" = EXCLUDED."categoryName",
      "totalItems" = EXCLUDED."totalItems",
      "totalRevenue" = EXCLUDED."totalRevenue"`)}async function p(t){await a.$executeRaw(e.Prisma.sql`
    INSERT INTO daily_customer_category_summary (
      date, "customerId", "regionId", "regionCode", status, "categoryId", "categoryName",
      "totalOrders", "totalRevenue", "totalItems", "createdAt", "updatedAt"
    )
    SELECT
      o."placedAt"::date,
      o."customerId",
      o."regionId",
      r.code,
      o.status,
      cat.id,
      cat.name,
      1,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0),
      coalesce(sum(oi.quantity), 0)::int,
      now(),
      now()
    FROM orders o
    JOIN order_items oi ON oi."orderId" = o.id
    JOIN products p     ON p.id = oi."productId"
    JOIN categories cat ON cat.id = p."categoryId"
    JOIN regions r      ON r.id = o."regionId"
    WHERE o.id = ${t}
    GROUP BY o."placedAt"::date, o."customerId", o."regionId", r.code, o.status, cat.id, cat.name
    ON CONFLICT (date, "customerId", "regionId", status, "categoryId")
    DO UPDATE SET
      "totalOrders"  = daily_customer_category_summary."totalOrders" + EXCLUDED."totalOrders",
      "totalRevenue" = daily_customer_category_summary."totalRevenue" + EXCLUDED."totalRevenue",
      "totalItems"   = daily_customer_category_summary."totalItems" + EXCLUDED."totalItems",
      "updatedAt"    = now()`)}async function $(t){await a.$executeRaw(e.Prisma.sql`
    INSERT INTO daily_filter_category_summary (
      date, "regionId", "regionCode", status, "categoryId", "categoryName",
      "totalOrders", "totalRevenue", "totalItems", "createdAt", "updatedAt"
    )
    SELECT
      o."placedAt"::date,
      o."regionId",
      r.code,
      o.status,
      cat.id,
      cat.name,
      1,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0),
      coalesce(sum(oi.quantity), 0)::int,
      now(),
      now()
    FROM orders o
    JOIN order_items oi ON oi."orderId" = o.id
    JOIN products p     ON p.id = oi."productId"
    JOIN categories cat ON cat.id = p."categoryId"
    JOIN regions r      ON r.id = o."regionId"
    WHERE o.id = ${t}
    GROUP BY o."placedAt"::date, o."regionId", r.code, o.status, cat.id, cat.name
    ON CONFLICT (date, "regionId", status, "categoryId")
    DO UPDATE SET
      "totalOrders"  = daily_filter_category_summary."totalOrders" + EXCLUDED."totalOrders",
      "totalRevenue" = daily_filter_category_summary."totalRevenue" + EXCLUDED."totalRevenue",
      "totalItems"   = daily_filter_category_summary."totalItems" + EXCLUDED."totalItems",
      "updatedAt"    = now()`)}async function _(t){await a.$executeRaw(e.Prisma.sql`
    INSERT INTO daily_status_category_summary (
      date, status, "categoryId", "categoryName",
      "totalOrders", "totalRevenue", "totalItems", "createdAt", "updatedAt"
    )
    SELECT
      o."placedAt"::date,
      o.status,
      cat.id,
      cat.name,
      1,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0),
      coalesce(sum(oi.quantity), 0)::int,
      now(),
      now()
    FROM orders o
    JOIN order_items oi ON oi."orderId" = o.id
    JOIN products p     ON p.id = oi."productId"
    JOIN categories cat ON cat.id = p."categoryId"
    WHERE o.id = ${t}
    GROUP BY o."placedAt"::date, o.status, cat.id, cat.name
    ON CONFLICT (date, status, "categoryId")
    DO UPDATE SET
      "totalOrders"  = daily_status_category_summary."totalOrders" + EXCLUDED."totalOrders",
      "totalRevenue" = daily_status_category_summary."totalRevenue" + EXCLUDED."totalRevenue",
      "totalItems"   = daily_status_category_summary."totalItems" + EXCLUDED."totalItems",
      "updatedAt"    = now()`)}async function T(t){await a.$executeRaw(e.Prisma.sql`
    INSERT INTO daily_customer_token_category_summary (
      date, token, "regionId", "regionCode", status, "categoryId", "categoryName",
      "totalOrders", "totalRevenue", "totalItems", "createdAt", "updatedAt"
    )
    SELECT
      o."placedAt"::date,
      t.token,
      o."regionId",
      r.code,
      o.status,
      cat.id,
      cat.name,
      1,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0),
      coalesce(sum(oi.quantity), 0)::int,
      now(),
      now()
    FROM orders o
    JOIN customers c   ON c.id = o."customerId"
    JOIN order_items oi ON oi."orderId" = o.id
    JOIN products p     ON p.id = oi."productId"
    JOIN categories cat ON cat.id = p."categoryId"
    JOIN regions r      ON r.id = o."regionId"
    CROSS JOIN LATERAL (
      SELECT DISTINCT token
      FROM unnest(ARRAY[
        lower(c."firstName"),
        lower(c."lastName"),
        lower(c.email),
        lower(split_part(c.email, '@', 1))
      ]) AS token
      WHERE token <> ''
    ) t
    WHERE o.id = ${t}
    GROUP BY o."placedAt"::date, t.token, o."regionId", r.code, o.status, cat.id, cat.name
    ON CONFLICT (date, token, "regionId", status, "categoryId")
    DO UPDATE SET
      "totalOrders"  = daily_customer_token_category_summary."totalOrders" + EXCLUDED."totalOrders",
      "totalRevenue" = daily_customer_token_category_summary."totalRevenue" + EXCLUDED."totalRevenue",
      "totalItems"   = daily_customer_token_category_summary."totalItems" + EXCLUDED."totalItems",
      "updatedAt"    = now()`)}async function f(t){await a.$executeRaw(e.Prisma.sql`
    INSERT INTO daily_customer_token_category_rollup (
      date, token, "categoryId", "categoryName",
      "totalOrders", "totalRevenue", "totalItems", "createdAt", "updatedAt"
    )
    SELECT
      o."placedAt"::date,
      t.token,
      cat.id,
      cat.name,
      1,
      coalesce(sum(oi.quantity * oi."unitPrice" * (1 - oi.discount)), 0),
      coalesce(sum(oi.quantity), 0)::int,
      now(),
      now()
    FROM orders o
    JOIN customers c    ON c.id = o."customerId"
    JOIN order_items oi ON oi."orderId" = o.id
    JOIN products p     ON p.id = oi."productId"
    JOIN categories cat ON cat.id = p."categoryId"
    CROSS JOIN LATERAL (
      SELECT DISTINCT token
      FROM unnest(ARRAY[
        lower(c."firstName"),
        lower(c."lastName"),
        lower(c.email),
        lower(split_part(c.email, '@', 1))
      ]) AS token
      WHERE token <> ''
    ) t
    WHERE o.id = ${t}
    GROUP BY o."placedAt"::date, t.token, cat.id, cat.name
    ON CONFLICT (date, token, "categoryId")
    DO UPDATE SET
      "totalOrders"  = daily_customer_token_category_rollup."totalOrders" + EXCLUDED."totalOrders",
      "totalRevenue" = daily_customer_token_category_rollup."totalRevenue" + EXCLUDED."totalRevenue",
      "totalItems"   = daily_customer_token_category_rollup."totalItems" + EXCLUDED."totalItems",
      "updatedAt"    = now()`)}async function C(t){await a.$executeRaw(e.Prisma.sql`
    INSERT INTO daily_customer_token_order_summary (
      date, token, "regionId", "regionCode", status,
      "totalOrders", "totalRevenue", "createdAt", "updatedAt"
    )
    SELECT
      o."placedAt"::date,
      t.token,
      o."regionId",
      r.code,
      o.status,
      1,
      o.total,
      now(),
      now()
    FROM orders o
    JOIN customers c ON c.id = o."customerId"
    JOIN regions r   ON r.id = o."regionId"
    CROSS JOIN LATERAL (
      SELECT DISTINCT token
      FROM unnest(ARRAY[
        lower(c."firstName"),
        lower(c."lastName"),
        lower(c.email),
        lower(split_part(c.email, '@', 1))
      ]) AS token
      WHERE token <> ''
    ) t
    WHERE o.id = ${t}
    ON CONFLICT (date, token, "regionId", status)
    DO UPDATE SET
      "totalOrders"  = daily_customer_token_order_summary."totalOrders" + EXCLUDED."totalOrders",
      "totalRevenue" = daily_customer_token_order_summary."totalRevenue" + EXCLUDED."totalRevenue",
      "updatedAt"    = now()`)}let P=["PENDING","CONFIRMED","PROCESSING","SHIPPED","DELIVERED","CANCELLED","REFUNDED"],D={placedAt:t=>({placedAt:t}),total:t=>({total:t}),status:t=>({status:t}),customer:t=>({customer:{lastName:t}})},w={placedAt:'o."placedAt"',total:"o.total",status:"o.status",customer:'c."lastName"'};function h(t){let e=t?.trim().toLowerCase();return e&&/^[a-z0-9._@-]+$/.test(e)?e:null}function L(t){return t.replace(/[%_]/g,"")}let q=new Map,M=new Map,Y=new Map;function v(t){let r=t.trim(),o=r.toLowerCase(),s=Date.now(),i=M.get(o);if(i&&i.expiresAt>s)return i.promise;let d=`%${L(r)}%`,n=a.$queryRaw(e.Prisma.sql`
    SELECT id FROM orders WHERE notes ILIKE ${d} LIMIT 1`).then(t=>t.length>0);return M.set(o,{expiresAt:s+6e4,promise:n}),n.catch(()=>M.delete(o)),n}function F(t){let r=t.trim(),o=r.toLowerCase(),s=Date.now(),i=q.get(o);if(i&&i.expiresAt>s)return i.promise;let d=`%${L(r)}%`,n=h(r),l=Promise.all([n?a.$queryRaw(e.Prisma.sql`
          SELECT EXISTS (
            SELECT 1
            FROM daily_customer_token_order_summary
            WHERE token = ${n}
            LIMIT 1
          ) AND EXISTS (
            SELECT 1
            FROM customers
            WHERE lower("firstName") = ${n}
               OR lower("lastName") = ${n}
            LIMIT 1
          ) AS ready`):Promise.resolve([{ready:!1}]),a.$queryRaw(e.Prisma.sql`
      SELECT id FROM customers
      WHERE ("firstName" || ' ' || "lastName") ILIKE ${d}
      LIMIT ${5001}`),v(r)]).then(([t,e,a])=>({pattern:d,token:n,tokenOrderReady:!!t[0]?.ready,customerRows:e,notesHaveMatches:a}));return q.set(o,{expiresAt:s+6e4,promise:l}),l.catch(()=>q.delete(o)),l}function U(t){let r=t.trim(),o=r.toLowerCase(),s=Date.now(),i=Y.get(o);if(i&&i.expiresAt>s)return i.promise;let d=h(r),n=Promise.all([d?a.$queryRaw(e.Prisma.sql`
          SELECT EXISTS (
            SELECT 1
            FROM daily_customer_token_order_summary
            WHERE token = ${d}
            LIMIT 1
          ) AND EXISTS (
            SELECT 1
            FROM customers
            WHERE lower("firstName") = ${d}
               OR lower("lastName") = ${d}
            LIMIT 1
          ) AS ready`):Promise.resolve([{ready:!1}]),v(r)]).then(([t,e])=>({token:d,tokenOrderReady:!!t[0]?.ready,notesHaveMatches:e}));return Y.set(o,{expiresAt:s+6e4,promise:n}),n.catch(()=>Y.delete(o)),n}function k(t){return t?t.split(",").map(t=>t.trim()).filter(t=>t.length>0):[]}function J(t){return k(t).map(t=>t.toUpperCase()).filter(t=>P.includes(t))}function b(){let t=new Date,e=t.getFullYear(),a=String(t.getMonth()+1).padStart(2,"0"),r=String(t.getDate()).padStart(2,"0");return`${e}-${a}-${r}`}function H(t,e){if(null==t||""===t)return null;let a=new Date(t);if(Number.isNaN(a.getTime()))throw new o("BAD_REQUEST",`invalid date filter: ${t}`);return"end"===e&&/^\d{4}-\d{2}-\d{2}$/.test(t)&&a.setUTCHours(23,59,59,999),a}function W(t,e){if(null==t)return null;let a=Number(t);if(!Number.isFinite(a))throw new o("BAD_REQUEST",`invalid ${e}`);return a}async function x(t){let e=J(t.status),r=k(t.regionCode),o=null;r.length&&(o=(await a.region.findMany({where:{code:{in:r}},select:{id:!0}})).map(t=>t.id));let s=H(t.from,"start"),i=H(t.to||(t.from?b():t.to),"end"),d=W(t.minTotal,"minTotal"),n=W(t.maxTotal,"maxTotal"),l=e.length>0||null!==o||null!==s||null!==i||null!==d||null!==n;return{statuses:e,regionIds:o,from:s,to:i,minTotal:d,maxTotal:n,hasAny:l}}function B(t){let a=[];return t.statuses.length&&a.push(e.Prisma.sql`o.status = ANY(${t.statuses}::text[]::"OrderStatus"[])`),null!==t.regionIds&&a.push(e.Prisma.sql`o."regionId" = ANY(${t.regionIds})`),t.from&&a.push(e.Prisma.sql`o."placedAt" >= ${t.from}`),t.to&&a.push(e.Prisma.sql`o."placedAt" <= ${t.to}`),null!==t.minTotal&&a.push(e.Prisma.sql`o.total >= ${t.minTotal}`),null!==t.maxTotal&&a.push(e.Prisma.sql`o.total <= ${t.maxTotal}`),a}function X(t){return t.length?e.Prisma.sql`WHERE ${e.Prisma.join(t," AND ")}`:e.Prisma.empty}async function j(t){let a=t?.trim();if(!a)return null;let r=await U(a);if(r.token&&r.tokenOrderReady){let t=`%${L(a)}%`,o=r.notesHaveMatches?e.Prisma.sql`OR o.notes ILIKE ${t}`:e.Prisma.empty;return{pattern:t,matchJoin:e.Prisma.empty,condition:e.Prisma.sql`(
        lower(c."firstName") = ${r.token}
        OR lower(c."lastName") = ${r.token}
        ${o}
      )`,needsCustomerJoin:!0,exactCustomerToken:!0,noMatches:!1}}if(/^\d+$/.test(a)&&r.notesHaveMatches){let t=`%${L(a)}%`;return{pattern:t,matchJoin:e.Prisma.empty,condition:e.Prisma.sql`o.notes ILIKE ${t}`,needsCustomerJoin:!1,exactCustomerToken:!1,noMatches:!1}}let{pattern:o,token:s,tokenOrderReady:i,customerRows:d,notesHaveMatches:n}=await F(a);if(s&&i){let t=n?e.Prisma.sql`OR o.notes ILIKE ${o}`:e.Prisma.empty;return{pattern:o,matchJoin:e.Prisma.empty,condition:e.Prisma.sql`(
          lower(c."firstName") = ${s}
          OR lower(c."lastName") = ${s}
          ${t}
        )`,needsCustomerJoin:!0,exactCustomerToken:!0,noMatches:!1}}if(d.length>5e3){let t=n?e.Prisma.sql`OR o.notes ILIKE ${o}`:e.Prisma.empty;return{pattern:o,matchJoin:e.Prisma.empty,condition:e.Prisma.sql`((c."firstName" || ' ' || c."lastName") ILIKE ${o} ${t})`,needsCustomerJoin:!0,exactCustomerToken:!1,noMatches:!1}}let l=d.map(t=>t.id);if(0===l.length&&n)return{pattern:o,matchJoin:e.Prisma.empty,condition:e.Prisma.sql`o.notes ILIKE ${o}`,needsCustomerJoin:!1,exactCustomerToken:!1,noMatches:!1};if(0===l.length&&!n)return{pattern:o,matchJoin:e.Prisma.empty,condition:null,needsCustomerJoin:!1,exactCustomerToken:!1,noMatches:!0};let c=l.length?e.Prisma.sql`SELECT id FROM orders WHERE "customerId" = ANY(${l})`:e.Prisma.sql`SELECT id FROM orders WHERE false`,m=n?e.Prisma.sql`UNION SELECT id FROM orders WHERE notes ILIKE ${o}`:e.Prisma.empty;return{pattern:o,matchJoin:e.Prisma.sql`
      JOIN (
        ${c}
        ${m}
      ) text_match ON text_match.id = o.id`,condition:null,needsCustomerJoin:!1,exactCustomerToken:!1,noMatches:!1}}async function G(t){var r,o;let i=Math.max(Math.trunc(t.page??1)||1,1),d=Math.min(Math.max(Math.trunc(t.pageSize??20)||20,1),100),n=null!=(r=t.sort)&&r in D?r:"placedAt",l="asc"===(o=t.dir)||"desc"===o?o:"desc",c=t.q?.trim(),m=(i-1)*d;try{let r=await x(t);if(!c&&!r.hasAny){let r=[D[n](l),{id:l}],[o,s]=await Promise.all([a.order.findMany({skip:m,take:d,orderBy:r,select:{id:!0}}),a.order.count()]),c=await tt(o.map(t=>t.id)),u=0===s?0:Math.ceil(s/d),E={data:c,page:i,pageSize:d,total:s,totalPages:u,approximate:!1};return t.facets&&(E.facets=await z(e.Prisma.empty,e.Prisma.empty)),E}let o=B(r),s=e.Prisma.sql`JOIN customers c ON c.id = o."customerId"`,u=await j(c);if(u?.noMatches){let e={data:[],page:i,pageSize:d,total:0,totalPages:0,approximate:!1};return t.facets&&(e.facets={status:[],region:[],approximate:!1}),e}let E=[...u?.condition?[u.condition]:[],...o],y=X(E),I=u?.matchJoin??e.Prisma.empty,g=u?.needsCustomerJoin?s:I,O=r.hasAny&&o.length>0&&await Z(e.Prisma.empty,X(o))<=1e4,R=e.Prisma.raw(w[n]),N=e.Prisma.raw("asc"===l?"ASC":"DESC"),S=!!c&&!u?.needsCustomerJoin,A=u?.needsCustomerJoin||"customer"===n?s:e.Prisma.empty,p=e.Prisma.sql`${I} ${A}`,$=o.length?e.Prisma.sql`AND ${e.Prisma.join(o," AND ")}`:e.Prisma.empty,_=m+d,T=c&&c.length>=3&&u?.needsCustomerJoin?e.Prisma.sql`
            UNION
            SELECT id, sortkey FROM (
              SELECT o.id AS id, ${R} AS sortkey
              FROM orders o
              WHERE o.notes ILIKE ${u.pattern}
              ${$}
              ORDER BY ${R} ${N}, o.id ${N}
              LIMIT ${_}
            ) note_candidates`:e.Prisma.empty,f=u?.exactCustomerToken&&"customer"!==n?e.Prisma.sql`
          SELECT o.id
          FROM orders o
          JOIN customers c ON c.id = o."customerId"
          ${y}
          ORDER BY ${R} ${N}, o.id ${N}
          LIMIT ${d} OFFSET ${m}`:u?.needsCustomerJoin&&"customer"!==n?e.Prisma.sql`
          WITH candidates AS (
            SELECT id, sortkey FROM (
              SELECT o.id AS id, ${R} AS sortkey
              FROM orders o
              JOIN customers c ON c.id = o."customerId"
              WHERE (c."firstName" || ' ' || c."lastName") ILIKE ${u.pattern}
              ${$}
              ORDER BY ${R} ${N}, o.id ${N}
              LIMIT ${_}
            ) customer_candidates
            ${T}
          )
          SELECT id FROM candidates
          ORDER BY sortkey ${N}, id ${N}
          LIMIT ${d} OFFSET ${m}`:"customer"===n||S||O?e.Prisma.sql`
          WITH m AS MATERIALIZED (
            SELECT o.id AS id, ${R} AS sortkey
            FROM orders o ${p}
            ${y}
          )
          SELECT id FROM m ORDER BY sortkey ${N}, id ${N}
          LIMIT ${d} OFFSET ${m}`:e.Prisma.sql`
          SELECT o.id
          FROM orders o ${p}
          ${y}
          ORDER BY ${R} ${N}, o.id ${N}
          LIMIT ${d} OFFSET ${m}`,C=c&&u?.needsCustomerJoin?V(c,r).then(t=>t??Q(c,o)):K(g,y),[P,h]=await Promise.all([a.$queryRaw(f),C]),L=0===h?0:Math.ceil(h/d),q={data:await tt(P.map(t=>t.id)),page:i,pageSize:d,total:h,totalPages:L,approximate:!1};return t.facets&&(q.facets=await z(g,y)),q}catch(t){s(t,"listOrders")}}async function K(t,r){let o=await a.$queryRaw(e.Prisma.sql`
    SELECT count(*)::bigint AS count
    FROM orders o ${t} ${r}`);return Number(o[0]?.count??0)}async function V(t,r){if(null!==r.minTotal||null!==r.maxTotal)return null;let o=h(t);if(!o)return null;let s=await F(t);if(!s.tokenOrderReady)return null;let i=[e.Prisma.sql`token = ${o}`];r.from&&i.push(e.Prisma.sql`date >= ${r.from}::date`),r.to&&i.push(e.Prisma.sql`date <= ${r.to}::date`),r.statuses.length&&i.push(e.Prisma.sql`status = ANY(${r.statuses}::text[]::"OrderStatus"[])`),null!==r.regionIds&&i.push(e.Prisma.sql`"regionId" = ANY(${r.regionIds})`);let d=await a.$queryRaw(e.Prisma.sql`
    SELECT coalesce(sum("totalOrders"), 0)::bigint AS count
    FROM daily_customer_token_order_summary
    WHERE ${e.Prisma.join(i," AND ")}`),n=Number(d[0]?.count??0);if(!s.notesHaveMatches)return n;let l=B(r),c=l.length?e.Prisma.sql`AND ${e.Prisma.join(l," AND ")}`:e.Prisma.empty,m=await a.$queryRaw(e.Prisma.sql`
    SELECT count(*)::bigint AS count
    FROM orders o
    JOIN customers c ON c.id = o."customerId"
    WHERE o.notes ILIKE ${s.pattern}
      AND NOT (
        lower(c."firstName") = ${o}
        OR lower(c."lastName") = ${o}
      )
      ${c}`);return n+Number(m[0]?.count??0)}async function Q(t,r){let o=`%${L(t)}%`,s=(await a.$queryRaw(e.Prisma.sql`
    SELECT id FROM customers
    WHERE ("firstName" || ' ' || "lastName") ILIKE ${o}`)).map(t=>t.id),i=r.length?e.Prisma.sql`AND ${e.Prisma.join(r," AND ")}`:e.Prisma.empty,d=s.length?e.Prisma.sql`
        SELECT o.id
        FROM unnest(${s}::int[]) AS matched_customer(id)
        JOIN orders o ON o."customerId" = matched_customer.id
        ${i}`:e.Prisma.sql`SELECT id FROM orders WHERE false`,n=t.length>=3?e.Prisma.sql`
          UNION
          SELECT o.id
          FROM orders o
          WHERE o.notes ILIKE ${o}
          ${i}`:e.Prisma.empty,l=await a.$queryRaw(e.Prisma.sql`
    SELECT count(*)::bigint AS count
    FROM (
      ${d}
      ${n}
    ) matches`);return Number(l[0]?.count??0)}async function Z(t,r){let o=await a.$queryRaw(e.Prisma.sql`
    SELECT count(*)::bigint AS count FROM (
      SELECT 1 FROM orders o ${t} ${r} LIMIT ${10001}
    ) capped`);return Number(o[0]?.count??0)}async function z(t,r){let o=await a.$queryRaw(e.Prisma.sql`
    WITH base AS (
      SELECT o.status, o."regionId" FROM orders o ${t} ${r} LIMIT ${50001}
    )
    SELECT 'status' AS dim, status::text AS key, count(*)::bigint AS n FROM base GROUP BY status
    UNION ALL
    SELECT 'region' AS dim, "regionId"::text AS key, count(*)::bigint AS n FROM base GROUP BY "regionId"`),s=[],i=new Map,d=0;for(let t of o){let e=Number(t.n);"status"===t.dim?(s.push({value:t.key??"UNKNOWN",count:e}),d+=e):null!=t.key&&i.set(Number(t.key),e)}let n=[...i.keys()],l=new Map((n.length?await a.region.findMany({where:{id:{in:n}},select:{id:!0,code:!0}}):[]).map(t=>[t.id,t.code])),c=n.map(t=>({value:l.get(t)??String(t),count:i.get(t)}));return s.sort((t,e)=>e.count-t.count),c.sort((t,e)=>e.count-t.count),{status:s,region:c,approximate:d>5e4}}async function tt(t){return 0===t.length?[]:(await a.$queryRaw(e.Prisma.sql`
    WITH selected(id, ord) AS (
      SELECT * FROM unnest(${t}::int[]) WITH ORDINALITY
    )
    SELECT
      o.id,
      o.status::text AS status,
      o.total::float8 AS total,
      o.currency,
      o.notes,
      o."placedAt",
      json_build_object(
        'id', c.id,
        'email', c.email,
        'firstName', c."firstName",
        'lastName', c."lastName"
      ) AS customer,
      json_build_object(
        'id', r.id,
        'code', r.code,
        'name', r.name
      ) AS region,
      coalesce(
        json_agg(
          json_build_object(
            'id', oi.id,
            'productId', oi."productId",
            'quantity', oi.quantity,
            'unitPrice', oi."unitPrice"::float8,
            'discount', oi.discount::float8,
            'product', json_build_object(
              'id', p.id,
              'sku', p.sku,
              'name', p.name
            )
          )
          ORDER BY oi.id
        ) FILTER (WHERE oi.id IS NOT NULL),
        '[]'::json
      ) AS items
    FROM selected s
    JOIN orders o       ON o.id = s.id
    JOIN customers c    ON c.id = o."customerId"
    JOIN regions r      ON r.id = o."regionId"
    LEFT JOIN order_items oi ON oi."orderId" = o.id
    LEFT JOIN products p     ON p.id = oi."productId"
    GROUP BY s.ord, o.id, c.id, r.id
    ORDER BY s.ord`)).map(t=>({id:t.id,status:t.status,total:Number(t.total),currency:t.currency,notes:t.notes,placedAt:t.placedAt.toISOString(),customer:t.customer,region:t.region,items:t.items}))}async function te(t){if(!t.customerId||!t.regionId||!Array.isArray(t.items)||0===t.items.length)throw new o("BAD_REQUEST","customerId, regionId, and at least one item are required");for(let e of t.items)if(!e.productId||e.quantity<=0||e.unitPrice<0)throw new o("BAD_REQUEST","each item needs productId, a positive quantity, and a non-negative unitPrice");let e=t.items.reduce((t,e)=>t+e.quantity*e.unitPrice*(1-(e.discount??0)),0);try{let r=await a.order.create({data:{customerId:t.customerId,regionId:t.regionId,currency:t.currency??"USD",notes:t.notes??null,total:e,items:{create:t.items.map(t=>({productId:t.productId,quantity:t.quantity,unitPrice:t.unitPrice,discount:t.discount??0}))}}});if(t.items.length>0)try{let e=await a.product.findUnique({where:{id:t.items[0].productId},include:{category:!0}});e?.category?.name}catch{}return q.clear(),M.clear(),Y.clear(),await A(r.id),S(r.id).catch(()=>{}),p(r.id).catch(()=>{}),$(r.id).catch(()=>{}),_(r.id).catch(()=>{}),T(r.id).catch(()=>{}),f(r.id).catch(()=>{}),C(r.id).catch(()=>{}),{id:r.id,status:r.status,total:Number(r.total),placedAt:r.placedAt.toISOString()}}catch(t){s(t,"createOrder")}}let ta={region:{select:{id:!0,code:!0,name:!0}}};function tr(t){return{id:t.id,email:t.email,firstName:t.firstName,lastName:t.lastName,phone:t.phone,region:t.region,createdAt:t.createdAt.toISOString()}}function to(t){return{id:t.id,email:t.email,firstName:t.firstName,lastName:t.lastName,phone:t.phone,region:{id:t.regionId,code:t.regionCode,name:t.regionName},createdAt:t.createdAt.toISOString()}}async function ts(t){let r=Math.min(Math.max(t.limit??20,1),100),o=t.q?.trim();if(o){let i=`%${o.replace(/[%_]/g,"")}%`,d=t.cursor?e.Prisma.sql`AND c.id > ${t.cursor}`:e.Prisma.empty,n=t.regionId?e.Prisma.sql`AND c."regionId" = ${t.regionId}`:e.Prisma.empty;try{let t=await a.$queryRaw(e.Prisma.sql`
        SELECT
          c.id,
          c.email,
          c."firstName",
          c."lastName",
          c.phone,
          c."createdAt",
          r.id AS "regionId",
          r.code AS "regionCode",
          r.name AS "regionName"
        FROM customers c
        JOIN regions r ON r.id = c."regionId"
        WHERE (c."firstName" || ' ' || c."lastName" || ' ' || c.email) ILIKE ${i}
        ${d}
        ${n}
        ORDER BY c.id ASC
        LIMIT ${r+1}`),o=t.length>r,s=(o?t.slice(0,r):t).map(to),l=o?s[s.length-1].id:null;return{data:s,nextCursor:l,hasMore:o}}catch(t){s(t,"listCustomers")}}let i={...t.regionId?{regionId:t.regionId}:{},...o?{OR:[{email:{contains:o,mode:"insensitive"}},{firstName:{contains:o,mode:"insensitive"}},{lastName:{contains:o,mode:"insensitive"}}]}:{}};try{let e=await a.customer.findMany({where:i,take:r+1,...t.cursor?{cursor:{id:t.cursor},skip:1}:{},orderBy:{id:"asc"},include:ta}),o=e.length>r,s=(o?e.slice(0,r):e).map(tr),d=o?s[s.length-1].id:null;return{data:s,nextCursor:d,hasMore:o}}catch(t){s(t,"listCustomers")}}async function ti(){try{return await a.region.findMany({select:{id:!0,code:!0,name:!0},orderBy:{name:"asc"}})}catch(t){s(t,"listRegions")}}async function td(){try{let t=(await a.$queryRaw(e.Prisma.sql`
      SELECT
        (SELECT count(*) FROM customers) AS customers,
        (SELECT count(*) FROM products)  AS products`))[0];return{customers:Number(t.customers),products:Number(t.products)}}catch(t){s(t,"getSeedStats")}}t.s(["listCustomers",0,ts],34351),t.s(["listRegions",0,ti],59567),t.s(["getSeedStats",0,td],98325),t.s([],28228)}];

//# sourceMappingURL=%5Broot-of-the-server%5D__0gv46n_._.js.map