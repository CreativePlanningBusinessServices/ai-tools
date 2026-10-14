# SDF object types

Values for `--type` on `object:list` / `object:import`. They are **case-sensitive**: the three form
types are camelCase (`entryForm`, `transactionForm`, `addressForm`); everything else is lowercase.
In the project, each object is one XML file under `Objects/`, named `<scriptid>.xml`, whose root
element is the type. A new object's script id must start with the type's prefix and be lowercase
with underscores.

| UI name | `--type` | Script-id prefix |
|---|---|---|
| **Records, lists, segments** | | |
| Custom record type | `customrecordtype` | `customrecord_` |
| Custom list | `customlist` | `customlist_` |
| Custom segment (unified-id segments only) | `customsegment` | `cseg_` |
| Custom transaction type | `customtransactiontype` | `customtransaction_` |
| **Fields** | | |
| Entity field (customer, vendor, employee…) | `entitycustomfield` | `custentity_` |
| Transaction body field | `transactionbodycustomfield` | `custbody_` |
| Transaction line / column field | `transactioncolumncustomfield` | `custcol_` |
| Item field | `itemcustomfield` | `custitem_` |
| Item number field | `itemnumbercustomfield` | `custitemnumber_` |
| Item option field | `itemoptioncustomfield` | `custcol_` |
| CRM field (case, task, event, campaign) | `crmcustomfield` | `custevent_` |
| Other record field (custom record fields live inside the record type) | `othercustomfield` | `custrecord_` |
| **Forms and templates** | | |
| Custom entry form (records: customer, item, custom record…) | `entryForm` | `custform_` |
| Custom transaction form (sales order, invoice, deposit, journal…) | `transactionForm` | `custform_` |
| Custom address form | `addressForm` | `custform_` |
| Advanced PDF/HTML template | `advancedpdftemplate` | `custtmpl_` |
| Email template (to edit or create one, use the `netsuite-email-designer` skill; SDF for migrating whole templates) | `emailtemplate` | `custemailtmpl_` |
| **UI** | | |
| Subtab | `subtab` | `custtab_` |
| Sublist | `sublist` | `custsublist_` |
| Center, center category, center tab, center link | `center`, `centercategory`, `centertab`, `centerlink` | `custcenter_`, `custcentercategory_`, `custcentertab_`, `custcenterlink_` |
| Published dashboard | `publisheddashboard` | `custpubdashboard_` |
| KPI scorecard | `kpiscorecard` | `custkpiscorecard_` |
| **Scripts** (each import also pulls the `.js` into `FileCabinet/`) | | |
| Client script | `clientscript` | `customscript_` |
| User event script | `usereventscript` | `customscript_` |
| Suitelet | `suitelet` | `customscript_` |
| RESTlet | `restlet` | `customscript_` |
| Scheduled script | `scheduledscript` | `customscript_` |
| Map/Reduce script | `mapreducescript` | `customscript_` |
| Mass update script | `massupdatescript` | `customscript_` |
| Portlet | `portlet` | `customscript_` |
| Workflow action script | `workflowactionscript` | `customscript_` |
| Custom record action script | `customrecordactionscript` | `customscript_` |
| Bundle installation script | `bundleinstallationscript` | `customscript_` |
| SDF installation script | `sdfinstallationscript` | `customscript_` |
| **Plug-ins** | `plugintype`, `pluginimplementation`, `customglplugin`, `emailcaptureplugin`, `ficonnectivityplugin`, `bankstatementparserplugin`, `paymentgatewayplugin`, `promotionsplugin`, `shippingpartnersplugin`, `taxcalculationplugin`, `platformextensionplugin`, `advancedrevrecplugin`, `consolidatedrateadjustorplugin` | `customscript_` |
| **Workflow, search, analytics** | | |
| Workflow | `workflow` | `customworkflow_` |
| Saved search (to run, create, edit or delete one, use the `netsuite-saved-search` skill; SDF only migrates whole searches) | `savedsearch` | `customsearch_` |
| Saved CSV import | `savedcsvimport` | `custimport_` |
| Dataset | `dataset` | `custdataset_` |
| Workbook | `workbook` | `custworkbook_` |
| **Other** | | |
| Role | `role` | `customrole_` |
| Translation collection | `translationcollection` | `custcollection_` |
| Integration record | `integration` | `custinteg_` |
| Secret (API secret) | `secret` | `custsecret_` |
| SSP application / single page app | `sspapplication`, `singlepageapp` | `webapp_`, `custspa_` |
| CMS content type, commerce extension, commerce theme | `cmscontenttype`, `commerceextension`, `commercetheme` | `custcontenttype_`, `customextension_`, `custcommercetheme_` |

## Not supported by SDF (use the UI, or say so)

- Standard forms, standard roles, standard records: only `custform_*`, `customrole_*` and
  `customrecord_*` objects exist. A custom form names its base form in `standard="STANDARD…"`.
- Transaction form **legacy (non-advanced) PDF and HTML layouts**, online lead/case forms, web-site
  customization objects. Advanced PDF/HTML templates *are* supported (`advancedpdftemplate`).
- **Deleting** any object. SDF only creates and updates.
- Bundles (install and update them in the UI; a bundle's objects can be imported if unlocked).
- Custom segments that do not use unified ids.
- The `<definition>` blob inside saved searches, workbooks and datasets. It is opaque: import and
  deploy whole searches, but make search changes in the UI.
- Custom fields that are part of a custom record type are deployed with the record type, not alone.

## Forms

- Forms cannot be authored from scratch; import an existing form and modify the XML.
- Script ids: `custform_<something>`; file name = script id. Imported ids look like
  `custform_12_1234567_345` (number, account, number) and carry no name; the name is `<name>`.
- `<name>` ≤ 60 characters. Renaming an existing form and deploying creates a *new* form; keep the
  script id and name together when you mean "update".
- Every `<field>` needs a `<label>` with a value (a single space works for "no label").
- `<preferred>T</preferred>` makes it the default form for the record type/role; copies should be `F`.
- `<recordType>` for custom record forms references the record type by script id, so the record
  type (or a dependency entry for it) must be in the project; `project:adddependencies` adds it.
- Fields in top/bottom positions cannot be moved, and `storedWithRecord` applies only to check and
  journal forms.
