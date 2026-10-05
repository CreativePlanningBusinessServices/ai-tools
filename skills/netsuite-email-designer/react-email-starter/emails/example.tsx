import { Body, Container, Head, Heading, Html, Img, Link, Preview, Section, Text } from '@react-email/components';
import * as React from 'react';
import { FreeMarker, NS, ns } from './_components/netsuite';

export default function InvoiceEmail() {
  return (
    <Html lang="en">
      <Head />
      {/* Preview accepts string children only, so use ns() rather than <NS /> here. */}
      <Preview>{`Invoice ${ns('transaction.tranid')} is ready`}</Preview>
      <Body style={{ fontFamily: 'Arial, Helvetica, sans-serif', backgroundColor: '#f4f4f5', margin: 0 }}>
        <Container style={{ maxWidth: 560, margin: '0 auto', padding: 24, backgroundColor: '#ffffff' }}>
          <Img src={ns('companyInformation.logoUrl')} alt={ns('companyInformation.companyName')} width="180" />
          <Heading as="h2">Invoice <NS expr="transaction.tranid" /></Heading>
          {/* recipient is absent when NetSuite validates the saved record, so it must be null-safe. */}
          <Text>Hello <NS expr='(recipient.firstName)!"there"' />,</Text>
          <Text>Your invoice dated <NS expr='transaction.trandate?string("MM/dd/yyyy")' /> is attached.</Text>
          <FreeMarker>{'<#if transaction.memo?has_content>'}</FreeMarker>
          <Text><NS expr="transaction.memo" /></Text>
          <FreeMarker>{'</#if>'}</FreeMarker>
          <Section>
            <Link href={ns('transaction.custbody_pay_link_url')}>Pay now</Link>
          </Section>
          <Text style={{ color: '#71717a', fontSize: 12 }}>
            Sent by <NS expr="companyInformation.companyName" />
          </Text>
        </Container>
      </Body>
    </Html>
  );
}
