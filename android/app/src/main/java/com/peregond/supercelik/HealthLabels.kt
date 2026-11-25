package com.peregond.supercelik

// Row/section key of the health card (HealthRows) -> string resource. Keep in sync with hl.py / LocCards.cs.
fun healthLabel(key: String): Int = when (key) {
    "hTitle" -> R.string.h_title
    "hNote" -> R.string.h_note
    "hSecPerson" -> R.string.h_sec_person
    "hSecCard" -> R.string.h_sec_card
    "hSecInsurance" -> R.string.h_sec_insurance
    "hSecCarrier" -> R.string.h_sec_carrier
    "hSecTaxpayer" -> R.string.h_sec_taxpayer
    "hLbo" -> R.string.h_lbo
    "hCardId" -> R.string.h_card_id
    "hInsurer" -> R.string.h_insurer
    "hIssued" -> R.string.h_issued
    "hValidUntil" -> R.string.h_valid_until
    "hPermanent" -> R.string.h_permanent
    "hBasis" -> R.string.h_basis
    "hInsuredFrom" -> R.string.h_insured_from
    "hBranch" -> R.string.h_branch
    "hOffice" -> R.string.h_office
    "hRfzoNo" -> R.string.h_rfzo_no
    "hIssuerCode" -> R.string.h_issuer_code
    "hExempt" -> R.string.h_exempt
    "hRelation" -> R.string.h_relation
    "hFamilyMember" -> R.string.h_family_member
    "hCarrierName" -> R.string.h_carrier_name
    "hCarrierLbo" -> R.string.h_carrier_lbo
    "hCarrierJmbg" -> R.string.h_carrier_jmbg
    "hTaxName" -> R.string.h_tax_name
    "hTaxResidence" -> R.string.h_tax_residence
    "hTaxPib" -> R.string.h_tax_pib
    "hTaxId" -> R.string.h_tax_id
    "hTaxActivity" -> R.string.h_tax_activity
    "hSurname" -> R.string.h_surname
    "hGivenName" -> R.string.h_given_name
    "hParent" -> R.string.h_parent
    "hDob" -> R.string.h_dob
    "hSex" -> R.string.h_sex
    "hJmbg" -> R.string.h_jmbg
    "hAddress" -> R.string.h_address
    else -> R.string.h_title
}
