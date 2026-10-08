#!/usr/bin/env bash
# Paste into the migration repository root and run: bash 4_install_skill_osb_templates.sh
# Installs skill osb-to-camel: assets/templates. Existing files are overwritten.
set -euo pipefail
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/FLOW_CARD.md")"
cat > '.pi/skills/osb-to-camel/assets/templates/FLOW_CARD.md' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_FLOW_CARD_MD'
# Flow card: {{proxy_ref}}

| | |
|---|---|
| **OSB project / folder** | {{project}} |
| **Proxy service** | `{{proxy_ref}}` ({{proxy_path}}) |
| **Pipeline** | `{{pipeline_ref}}` ({{pipeline_path}}) |
| **Triage** | {{tier}} (score {{score}}): {{reasons}} |
| **Target** | Camel {{camel_version}} on Spring Boot {{spring_boot_version}}, Java DSL, module `{{module}}`, package `{{package}}` |
| **Status** | draft / approved / implemented / tested / recorded |
| **Owner of the approval** | |

## 1. Contract (must not change)

| Item | Value | Source |
|---|---|---|
| Inbound transport | {{proxy_transport}} | proxy `endpointConfig/provider-id` |
| Inbound URI (kept for the Apigee route rule) | {{proxy_uris}} | proxy `URI` |
| Binding | {{binding}}, SOAP 1.2 = {{soap12}} | proxy `binding` |
| WSDL / port | {{wsdl}} | proxy `binding/wsdl` |
| Operations | {{operations}} | pipeline operational branch, WSDL |
| Security on the inbound | {{inbound_security}} | proxy provider-specific, WS-policy |
| JMS topic subscription (if `is-queue=false`) | durable / distribution / selector from the inbound transport row | proxy `inbound-properties`; target = named subscription queue + broker filter, consumed by FQQN (transport mapping) |
| Camel inbound endpoint | | decided here |

## 2. Pipeline walk (one row per OSB action, in execution order)

| # | Pipeline / stage | OSB action | What it does (from the XML) | Proposed Camel step | Decision / deviation reason |
|---|---|---|---|---|---|
{{action_rows}}

Error handlers in scope: {{error_handler_scopes}}

## 3. Context variables

| OSB variable | Set by | Read by | Camel: header / property / body | Note |
|---|---|---|---|---|
{{variable_rows}}

## 4. Backends (business services)

| Business service | Transport / binding | URI(s) | Timeout | Retries (count / interval / app errors) | Service account | Camel endpoint | Config keys |
|---|---|---|---|---|---|---|---|
{{backend_rows}}

## 5. Transforms

| Resource | Kind | Lines | XQuery version | `fn-bea:` used | External params | Plan (keep + shim / keep / rewrite because) |
|---|---|---|---|---|---|---|
{{transform_rows}}

## 6. Error handling

| Scope | OSB handler | Actions in the handler | Camel construct | Fault shape returned |
|---|---|---|---|---|
{{error_rows}}

## 7. Non-functional and platform items

| Item | OSB value | Target decision | Owner if open |
|---|---|---|---|
| Retries / timeouts | see §4 | | |
| Throttling | {{throttling}} | | |
| Result caching | {{result_caching}} | | |
| Transactions (JMS) | {{transactional}} | | |
| WS-Security policies | {{ws_policies}} | | |
| Alert destinations | {{alert_destinations}} | | |
| Personal data in log expressions | | | |
| Correlation header | | | |

## 8. Test matrix (every row becomes a test)

| ID | Type | Scenario | Input fixture | Expected from | Mocks |
|---|---|---|---|---|---|
{{test_rows}}

## 9. Open items

| ID | Item | Why it blocks or not | Owner |
|---|---|---|---|
{{open_items}}

## 10. Approval

- [ ] Mapping decisions reviewed against the pipeline XML (not only the inventory)
- [ ] Contract unchanged (WSDL, port, SOAPAction, URI path)
- [ ] Every backend has config keys and a mock plan
- [ ] Every transform has a golden plan
- [ ] Every open item has an owner
- Approved by: ______ on ______
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_FLOW_CARD_MD
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/MIGRATION_RECORD.md")"
cat > '.pi/skills/osb-to-camel/assets/templates/MIGRATION_RECORD.md' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_MIGRATION_RECORD_MD'
# Migration record: {{proxy_ref}}

| | |
|---|---|
| **Flow card** | `migration/{{flow}}/FLOW_CARD.md` (approved {{approved_on}} by {{approved_by}}) |
| **Module** | `{{module}}`, routes `{{route_class}}`, resources `src/main/resources/osb/{{project}}/` |
| **Tier** | {{tier}} (score {{score}}) |
| **State** | implemented / tests green / parity pending / ready for cutover |
| **Effort actually spent** (design / code / tests / review) | | 

## 1. Outcome in five lines

- What the flow does:
- What changed structurally (one route per operation, sub-routes, publish as wire tap, ...):
- What is identical by construction (WSDL, path, transforms kept, error codes):
- What is different and why (see §4):
- What is still open (see §6):

## 2. Action-to-code map

| OSB action id | Pipeline / stage / action | Camel location (`class:line` or route id + step) | Mapping reference |
|---|---|---|---|
{{action_code_rows}}

## 3. Test results

| Test ID (card §8) | Class and method | Result | Evidence |
|---|---|---|---|
{{test_result_rows}}

Suite command and summary: `mvn -q test` → {{tests_run}} run, {{tests_failed}} failed, {{tests_skipped}} skipped.

## 4. Deviations from the original behaviour

| # | Original behaviour | Target behaviour | Reason | Approved by |
|---|---|---|---|---|

## 5. Configuration keys and their sources

| Key | Example value (non-prod) | Source in OSB | Delivered by (Vault / overlay / default) |
|---|---|---|---|
{{config_rows}}

## 6. Open items

| ID | Item | Owner | Blocks cutover? |
|---|---|---|---|
{{open_items}}

## 7. Cutover note (proposal; the operational decision is taken elsewhere)

- Apigee route rule to switch: proxy `{{apigee_proxy}}` target from OSB `{{osb_uri}}` to the service route `{{camel_path}}`, per flow, canary share first.
- OSB proxy stays deployed and reachable until the soak period ends; rollback = revert the route rule.
- Destinations that must exist on the target broker before cutover: {{destinations}}.
- Backend credentials in Vault before cutover: {{credential_keys}}.
- Parity status at cutover: {{parity_status}}.

## 8. Evidence files

- Inventory: `osb-inventory/flows/{{flow}}.json`
- Card: `migration/{{flow}}/FLOW_CARD.md`
- Fixtures: `src/test/resources/fixtures/{{flow}}/`, `src/test/resources/parity/{{flow}}/`
- Original transforms kept for the golden tests: `src/test/resources/osb-original/{{project}}/`
- Test report: `target/surefire-reports/`
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_MIGRATION_RECORD_MD
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/application-test.yml")"
cat > '.pi/skills/osb-to-camel/assets/templates/application-test.yml' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_APPLICATION_TEST_YML'
# Test profile for a migrated OSB module. Every external endpoint points at a mock; the values are overridden per test
# class (WireMock port, Artemis container URL) through @DynamicPropertySource.
camel:
  springboot:
    name: osb-{{project}}-test
    main-run-controller: true
  component:
    amqp:
      # overridden by the ArtemisContainer in JmsPublishTest; left unresolvable on purpose so a test that forgets
      # to override fails fast instead of connecting somewhere
      connection-factory: "#amqpConnectionFactory"

osb:
  proxy:
    {{ProxyName}}:
      path: {{osb_uri}}
  business:
    # one block per business service on the card; mirrors the production keys so the same route code runs
    {{BusinessName}}:
      url: http://localhost:0/overridden-by-test
      timeout: {{timeout_ms}}
      retry-count: {{retry_count}}
      retry-interval: {{retry_interval_ms}}
      username: test-user
      password: test-password

logging:
  level:
    org.apache.camel: INFO
    {{package}}: DEBUG
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_APPLICATION_TEST_YML
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/java/BackendContractTestTemplate.java")"
cat > '.pi/skills/osb-to-camel/assets/templates/java/BackendContractTestTemplate.java' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_BACKENDCONTRACTTESTTEMPLATE_JAVA'
package {{package}}.{{project_pkg}};

import com.github.tomakehurst.wiremock.junit5.WireMockExtension;
import org.apache.camel.ProducerTemplate;
import org.apache.camel.component.cxf.common.message.CxfConstants;
import org.apache.camel.test.spring.junit5.CamelSpringBootTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.RegisterExtension;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import static com.github.tomakehurst.wiremock.client.WireMock.*;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.wireMockConfig;
import static org.assertj.core.api.Assertions.assertThat;

/**
 * TEMPLATE: backend contract test. The route runs with its real CXF/HTTP producers against WireMock, which plays the
 * business services. Proves (a) the request the route sends, (b) timeout + retry behaviour as the business service
 * was configured in OSB, (c) that application faults are NOT retried (retry-application-errors=false),
 * (d) header propagation. Stub bodies come from fixtures/{{flow}}/backend/<BusinessService>/ (schema-derived or
 * recorded; the parity test reuses the recorded ones).
 */
@CamelSpringBootTest
@SpringBootTest(classes = {{ProxyName}}Route.class)
@ActiveProfiles("test")
class {{ProxyName}}BackendContractTest {

    @RegisterExtension
    static WireMockExtension backends = WireMockExtension.newInstance().options(wireMockConfig().dynamicPort().usingFilesUnderDirectory("src/test/resources/fixtures/{{flow}}/backend")).build();

    static final Map<String, String> NS = Map.of("mem", "http://example.com/member/v2", "ns", "http://example.com/integration/contributor/v1");

    @DynamicPropertySource
    static void pointBackendsAtWireMock(DynamicPropertyRegistry r) {
        r.add("osb.business.ContributorCoreBS.url", () -> backends.baseUrl() + "/ContributorService");
        r.add("osb.business.MemberLookupBS.url", () -> backends.baseUrl() + "/MemberLookup/v2");
        r.add("osb.business.ContributorCoreBS.timeout", () -> "1000");        // 1 s in the test, 30 s in OSB: same shape
        r.add("osb.business.ContributorCoreBS.retry-count", () -> "1");       // OSB retry-count 1
        r.add("osb.business.ContributorCoreBS.retry-interval", () -> "100");
    }

    @Autowired ProducerTemplate template;

    String fixture(String n) throws Exception { return Files.readString(Path.of("src/test/resources/fixtures/{{flow}}").resolve(n)); }

    /** C-01 the request to the core backend carries the transformed body and the correlation header. */
    @Test
    void coreReceivesTransformedRequest_withCorrelationHeader() throws Exception {
        backends.stubFor(post(urlPathEqualTo("/MemberLookup/v2")).withHeader("SOAPAction", containing("lookupMember"))
            .willReturn(okXml(fixture("backend/MemberLookupBS/lookupMember-active-response.xml"))));
        backends.stubFor(post(urlPathEqualTo("/ContributorService")).withHeader("SOAPAction", containing("getContributor"))
            .willReturn(okXml(fixture("backend/ContributorCoreBS/getContributor-response.xml"))));

        template.sendBodyAndHeaders("cxf:bean:{{proxyName}}Endpoint?dataFormat=PAYLOAD", fixture("01-getContributor-active-input.xml"),
            Map.of(CxfConstants.OPERATION_NAME, "getContributor", "X-Correlation-Id", "test-correlation"));

        backends.verify(postRequestedFor(urlPathEqualTo("/ContributorService"))
            .withHeader("X-Correlation-Id", equalTo("test-correlation"))
            .withRequestBody(matchingXPath("//ns:getContributorRequest[ns:contributorId='test-contributorId']", NS)));
    }

    /** C-02 timeout on the core backend: exactly retry-count + 1 attempts, then the OSB-380001 fault. */
    @Test
    void coreTimeout_isRetriedOnce_thenFaults() throws Exception {
        backends.stubFor(post(urlPathEqualTo("/MemberLookup/v2")).willReturn(okXml(fixture("backend/MemberLookupBS/lookupMember-active-response.xml"))));
        backends.stubFor(post(urlPathEqualTo("/ContributorService")).willReturn(okXml("<x/>").withFixedDelay(1500)));

        var exchange = template.send("cxf:bean:{{proxyName}}Endpoint?dataFormat=PAYLOAD", e -> {
            e.getMessage().setBody(fixture("01-getContributor-active-input.xml"));
            e.getMessage().setHeader(CxfConstants.OPERATION_NAME, "getContributor");
        });

        backends.verify(exactly(2), postRequestedFor(urlPathEqualTo("/ContributorService")));
        assertThat(exchange.getMessage().getHeader("osb.fault.errorCode", String.class)).isEqualTo("OSB-380001");
    }

    /** C-03 a SOAP fault from the backend is an application error: no retry (retry-application-errors=false). */
    @Test
    void coreSoapFault_isNotRetried() throws Exception {
        backends.stubFor(post(urlPathEqualTo("/MemberLookup/v2")).willReturn(okXml(fixture("backend/MemberLookupBS/lookupMember-active-response.xml"))));
        backends.stubFor(post(urlPathEqualTo("/ContributorService")).willReturn(aResponse().withStatus(500)
            .withHeader("Content-Type", "text/xml").withBody(fixture("backend/ContributorCoreBS/soap-fault-response.xml"))));

        template.send("cxf:bean:{{proxyName}}Endpoint?dataFormat=PAYLOAD", e -> {
            e.getMessage().setBody(fixture("01-getContributor-active-input.xml"));
            e.getMessage().setHeader(CxfConstants.OPERATION_NAME, "getContributor");
        });

        backends.verify(exactly(1), postRequestedFor(urlPathEqualTo("/ContributorService")));
    }
}
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_BACKENDCONTRACTTESTTEMPLATE_JAVA
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/java/JmsPublishTestTemplate.java")"
cat > '.pi/skills/osb-to-camel/assets/templates/java/JmsPublishTestTemplate.java' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_JMSPUBLISHTESTTEMPLATE_JAVA'
package {{package}}.{{project_pkg}};

import org.apache.camel.ConsumerTemplate;
import org.apache.camel.ProducerTemplate;
import org.apache.camel.test.spring.junit5.CamelSpringBootTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.activemq.ArtemisContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * TEMPLATE: the OSB publish to a JMS business service, proven against a throwaway Artemis (Testcontainers).
 * Proves: the proxy response does not wait for the publish (InOnly), exactly one message lands on the destination
 * with the body the outbound transform built, and (for transactional proxies) a failure after the publish rolls it
 * back. Requires Docker; when Docker is absent the test is disabled and the migration record says so.
 */
@Testcontainers(disabledWithoutDocker = true)
@CamelSpringBootTest
@SpringBootTest(classes = {{ProxyName}}Route.class)
@ActiveProfiles("test")
class {{ProxyName}}JmsPublishTest {

    @Container
    static final ArtemisContainer ARTEMIS = new ArtemisContainer("apache/activemq-artemis:2.42.0-alpine")   // pin per versions.md
        .withUser("test").withPassword("test");

    @DynamicPropertySource
    static void broker(DynamicPropertyRegistry r) {
        // AMQP 1.0 on 5672, the protocol the programme uses towards Red Hat AMQ Broker
        r.add("camel.component.amqp.remote-uri", () -> "amqp://" + ARTEMIS.getHost() + ":" + ARTEMIS.getMappedPort(5672));
        r.add("camel.component.amqp.username", () -> "test");
        r.add("camel.component.amqp.password", () -> "test");
        r.add("osb.business.AuditQueueBS.destination", () -> "APP.AUDIT.QUEUE");
    }

    @Autowired ProducerTemplate producer;
    @Autowired ConsumerTemplate consumer;

    /** J-01 one audit message per getContributor, body as built by the outbound transform. */
    @Test
    void publish_putsExactlyOneAuditMessageOnTheQueue() {
        producer.sendBody("direct:{{ProxyName}}-publishAudit", "<ignored/>");   // the publish sub-route builds its own body
        String msg = consumer.receiveBody("amqp:queue:APP.AUDIT.QUEUE", 5000, String.class);
        assertThat(msg).contains("<op>getContributor</op>");
        assertThat(consumer.receiveBodyNoWait("amqp:queue:APP.AUDIT.QUEUE")).isNull();
    }
}
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_JMSPUBLISHTESTTEMPLATE_JAVA
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/java/OsbRouteTemplate.java")"
cat > '.pi/skills/osb-to-camel/assets/templates/java/OsbRouteTemplate.java' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_OSBROUTETEMPLATE_JAVA'
package {{package}}.{{project_pkg}};

import {{package}}.osb.OsbSupport.OsbBodyWrapper;
import {{package}}.osb.OsbSupport.OsbFaultException;
import {{package}}.osb.OsbSupport.OsbFaultProcessor;
import {{package}}.osb.OsbSupport.OsbXQuery;
import org.apache.camel.ExchangePattern;
import org.apache.camel.LoggingLevel;
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.component.cxf.common.message.CxfConstants;
import org.springframework.stereotype.Component;

import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.util.Map;

/**
 * TEMPLATE for one migrated OSB proxy service. Replace the {{placeholders}}; keep the structure.
 *
 * Shape (why it looks like this):
 *  - one inbound route = the OSB proxy; it dispatches by WSDL operation like the OSB operational branch;
 *  - one direct: sub-route per operation = the OSB pipeline pair (request stages, route node, response stages);
 *  - every backend endpoint is a {{placeholder}}; every retry/timeout comes from configuration; the test replaces the
 *    endpoints with mocks (AdviceWith) by their step ids;
 *  - OSB expressions run through OsbXQuery with OSB variable semantics ($body, $memberResp, $inbound) and are copied
 *    from the pipeline XML verbatim, so the card's action ids map to lines here one to one;
 *  - $body handling: wrap() once at the inbound, unwrap() BEFORE EVERY backend call, rewrap() after a request-response
 *    call so the response pipeline sees the backend response as $body, unwrap() at the reply;
 *  - error handlers at the scope the flow card decided: stage (doTry), route node (onException on the backend segment),
 *    service (route-level onException that runs the OSB error pipeline).
 *
 * Route ids and step ids are the OSB names and action ids, so logs, metrics, tests and the migration record speak the
 * same language as the export.
 */
@Component
public class {{ProxyName}}Route extends RouteBuilder {

    // the pipeline's userNsDecl list, copied from the pipeline XML (<con:context>)
    static final Map<String, String> NS = Map.of(
        "ns", "http://example.com/integration/contributor/v1",
        "mem", "http://example.com/member/v2",
        "ctx", "http://www.bea.com/wli/sb/context",
        "tp", "http://www.bea.com/wli/sb/transports",
        "http", "http://www.bea.com/wli/sb/transports/http");

    // OSB variable names kept as exchange property names; they must not leak onto the wire, so never headers
    static final String P_CONTRIBUTOR_ID = "contributorId";
    static final String P_MEMBER_REQ = "memberReq";
    static final String P_MEMBER_RESP = "memberResp";

    // backend endpoints; address, timeouts and WSDL come from configuration, never literals
    static final String EP_CORE = "cxf:{{osb.business.ContributorCoreBS.url}}?wsdlURL=classpath:osb/{{project}}/WSDL/ContributorEnquiry.wsdl"
        + "&serviceName={http://example.com/integration/contributor/v1}ContributorEnquiryService&portName={http://example.com/integration/contributor/v1}ContributorEnquiryPort"
        + "&dataFormat=PAYLOAD&properties.org.apache.cxf.transport.http.receiveTimeout={{osb.business.ContributorCoreBS.timeout}}";
    static final String EP_MEMBER = "cxf:{{osb.business.MemberLookupBS.url}}?wsdlURL=classpath:osb/{{project}}/WSDL/MemberLookup.wsdl"
        + "&serviceName={http://example.com/member/v2}MemberLookupService&portName={http://example.com/member/v2}MemberLookupPort"
        + "&dataFormat=PAYLOAD&properties.org.apache.cxf.transport.http.receiveTimeout={{osb.business.MemberLookupBS.timeout}}";
    static final String EP_AUDIT = "amqp:queue:{{osb.business.AuditQueueBS.destination}}";

    @Override
    public void configure() {

        // --- service-level error handler = the OSB error pipeline "ServiceErrorHandler" -----------------------------
        onException(Exception.class)
            .handled(true)
            .process(new OsbFaultProcessor()).id("fault-context")                 // $fault/* -> headers + <ctx:fault> body
            .to("xslt-saxon:classpath:osb/{{project}}/Transform/ContributorFault.xsl").id("_ActionId-13")   // original fault XSLT, unchanged
            .log(LoggingLevel.WARN, "{{logger}}", "ALERT OpsAlert major: ${header.osb.fault.errorCode}").id("_ActionId-14")
            .to("micrometer:counter:osb.alert?tags=flow={{ProxyName}},severity=major")
            .process(OsbFaultProcessor::replyWithSoapFault).id("_ActionId-reply-error");   // OSB reply isErrorReply=true

        // --- backend retry = business service retry-count / retry-interval, transport failures only (retry-application-errors=false)
        onException(ConnectException.class, SocketTimeoutException.class)
            .onWhen(exchangeProperty("osb.backend").isEqualTo("ContributorCoreBS"))
            .maximumRedeliveries("{{osb.business.ContributorCoreBS.retry-count}}")
            .redeliveryDelay("{{osb.business.ContributorCoreBS.retry-interval}}")
            .useOriginalMessage().logRetryAttempted(true)
            .handled(false);                                                      // after the last retry the service handler maps the fault

        // --- inbound = the OSB proxy: same WSDL, same port, same path; PAYLOAD mode so $body == SOAP Body content ---
        from("cxf:/{{osb.proxy.ContributorEnquiryPS.path}}?wsdlURL=classpath:osb/{{project}}/WSDL/ContributorEnquiry.wsdl"
             + "&serviceName={http://example.com/integration/contributor/v1}ContributorEnquiryService"
             + "&portName={http://example.com/integration/contributor/v1}ContributorEnquiryPort&dataFormat=PAYLOAD")
            .routeId("{{ProxyName}}")
            .description("OSB proxy {{proxy_ref}} ({{proxy_uris}})")
            .process(OsbBodyWrapper.wrap()).id("osb-wrap")                       // <Body>payload</Body>: OSB $body semantics
            .setProperty("osb.operation", header(CxfConstants.OPERATION_NAME))
            .choice().id("OperationBranch")                                        // OSB operational branch
                .when(exchangeProperty("osb.operation").isEqualTo("getContributor")).to("direct:{{ProxyName}}-getContributor")
                .when(exchangeProperty("osb.operation").isEqualTo("updateContributor")).to("direct:{{ProxyName}}-updateContributor")
                .otherwise().throwException(new OsbFaultException("OSB-380002", "Unknown operation"))
            .end()
            .process(OsbBodyWrapper.unwrap()).id("osb-reply");                    // the reply is the bare payload

        // --- operation getContributor = pipeline pair GetContributorRequest / GetContributorResponse + route node ----
        from("direct:{{ProxyName}}-getContributor")
            .routeId("{{ProxyName}}-getContributor")
            .description("OSB pipeline GetContributorRequest -> RouteToCore -> GetContributorResponse")
            // stage ValidateAndEnrich
            .process(OsbBodyWrapper.unwrap()).to("validator:classpath:osb/{{project}}/XSD/Contributor.xsd").id("_ActionId-1").process(OsbBodyWrapper.rewrap())
            .setProperty(P_CONTRIBUTOR_ID, OsbXQuery.of("$body/ns:getContributorRequest/ns:contributorId/text()").ns(NS).asString()).id("_ActionId-2")
            .setProperty(P_MEMBER_REQ, OsbXQuery.of(
                "<mem:lookupMemberRequest><mem:nationalId>{ $body/ns:getContributorRequest/ns:nationalId/text() }</mem:nationalId></mem:lookupMemberRequest>")
                .ns(NS).asNode()).id("_ActionId-3")
            // _ActionId-4 service callout: send the request variable (bare), keep $body, capture the response variable
            .setProperty("osb.savedBody", body())
            .setBody(exchangeProperty(P_MEMBER_REQ))
            .setHeader(CxfConstants.OPERATION_NAME, constant("lookupMember"))
            .setProperty("osb.backend", constant("MemberLookupBS"))
            .to(EP_MEMBER).id("_ActionId-4")
            .setProperty(P_MEMBER_RESP, body())
            .setBody(exchangeProperty("osb.savedBody"))
            // _ActionId-5 ifThenElse on the callout result (OSB condition copied verbatim)
            .choice().id("_ActionId-5")
                .when(OsbXQuery.of("$memberResp/mem:lookupMemberResponse/mem:status/text() = 'ACTIVE'").ns(NS).asPredicate())
                    // _ActionId-6 replace $body contents-only with the stored XQuery, parameters bound by their OSB names
                    .process(OsbXQuery.resource("osb/{{project}}/Transform/MemberToContributor.xqy").ns(NS)
                                      .param("member", P_MEMBER_RESP, "$memberResp/mem:lookupMemberResponse")
                                      .param("contributorId", P_CONTRIBUTOR_ID)
                                      .replaceBodyContentsOnly()).id("_ActionId-6")
                    // _ActionId-7 transportHeaders copy-all=false: strip inbound headers, set the one the pipeline set
                    .removeHeaders("*", CxfConstants.OPERATION_NAME, "SOAPAction", "Content-Type")
                    .setHeader("X-Correlation-Id", OsbXQuery.of("$inbound/ctx:transport/ctx:request/tp:headers/http:X-Correlation-Id/text()").ns(NS).asString()).id("_ActionId-7")
                .otherwise()
                    .throwException(new OsbFaultException("AMN-4001", "Member is not active")).id("_ActionId-8")
            .end()
            // route node RouteToCore (_ActionId-15): terminal request-response call; the response pipeline follows
            .process(OsbBodyWrapper.unwrap())                                      // backend gets the bare payload
            .setHeader(CxfConstants.OPERATION_NAME, constant("getContributor"))
            .setProperty("osb.backend", constant("ContributorCoreBS"))
            .to(EP_CORE).id("_ActionId-15")
            .process(OsbBodyWrapper.rewrap())                                      // backend response is the new $body
            // response stage AuditAndLog
            .log(LoggingLevel.INFO, "{{logger}}", "getContributor done for ${exchangeProperty.contributorId}").id("_ActionId-9")
            .wireTap("direct:{{ProxyName}}-publishAudit").id("_ActionId-10")
            .end();

        // publish = one-way copy with its own outbound transform (_ActionId-11), InOnly on the broker
        from("direct:{{ProxyName}}-publishAudit")
            .routeId("{{ProxyName}}-publishAudit")
            .description("OSB publish to AuditQueueBS, response-required=false")
            .setBody(OsbXQuery.of("<audit><op>getContributor</op><id>{ $contributorId }</id></audit>").ns(NS).asNode()).id("_ActionId-11")
            .setExchangePattern(ExchangePattern.InOnly)
            .to(EP_AUDIT).id("publish-audit");

        // --- operation updateContributor: pass-through pipeline + route node ---------------------------------------
        from("direct:{{ProxyName}}-updateContributor")
            .routeId("{{ProxyName}}-updateContributor")
            .description("OSB pipeline UpdateContributorRequest -> RouteUpdateToCore")
            .log(LoggingLevel.DEBUG, "{{logger}}", "updateContributor").id("_ActionId-12")
            .process(OsbBodyWrapper.unwrap())
            .setHeader(CxfConstants.OPERATION_NAME, constant("updateContributor"))
            .setProperty("osb.backend", constant("ContributorCoreBS"))
            .to(EP_CORE).id("_ActionId-16")
            .process(OsbBodyWrapper.rewrap());
    }
}
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_OSBROUTETEMPLATE_JAVA
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/java/OsbRouteTestTemplate.java")"
cat > '.pi/skills/osb-to-camel/assets/templates/java/OsbRouteTestTemplate.java' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_OSBROUTETESTTEMPLATE_JAVA'
package {{package}}.{{project_pkg}};

import org.apache.camel.CamelContext;
import org.apache.camel.ExchangePattern;
import org.apache.camel.ProducerTemplate;
import org.apache.camel.builder.AdviceWith;
import org.apache.camel.component.cxf.common.message.CxfConstants;
import org.apache.camel.component.mock.MockEndpoint;
import org.apache.camel.test.spring.junit5.CamelSpringBootTest;
import org.apache.camel.test.spring.junit5.UseAdviceWith;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import org.xmlunit.assertj3.XmlAssert;

import static org.assertj.core.api.Assertions.assertThat;
// XMLUnit's XmlAssert.assertThat(Object) is NOT statically imported next to AssertJ's assertThat(String): for a String
// argument Java resolves to AssertJ's overload and the XML methods (and/areSimilar) do not compile. Qualify it.

/**
 * TEMPLATE: route test for one migrated OSB proxy. One @Test per row of the flow card's test matrix of type "route".
 * Everything outside the route is a mock: the CXF inbound is replaced by direct:in, and every backend call is replaced
 * BY ITS STEP ID (the OSB action id the route carries), so the test does not depend on how the endpoint URI is built.
 * No hostname of any real system appears here; that is the point.
 */
@CamelSpringBootTest
@SpringBootTest(classes = {{ProxyName}}Route.class)
@ActiveProfiles("test")
@UseAdviceWith
class {{ProxyName}}RouteTest {

    static final Path FIXTURES = Path.of("src/test/resources/fixtures/{{flow}}");

    @Autowired CamelContext context;
    @Autowired ProducerTemplate template;

    MockEndpoint core;      // replaces _ActionId-15 / _ActionId-16 (route node to ContributorCoreBS)
    MockEndpoint member;    // replaces _ActionId-4 (service callout to MemberLookupBS)
    MockEndpoint audit;     // replaces publish-audit (amqp)

    @BeforeEach
    void adviceRoutes() throws Exception {
        AdviceWith.adviceWith(context, "{{ProxyName}}", a -> a.replaceFromWith("direct:in"));
        AdviceWith.adviceWith(context, "{{ProxyName}}-getContributor", a -> {
            a.weaveById("_ActionId-4").replace().to("mock:member");
            a.weaveById("_ActionId-15").replace().to("mock:core");
            a.weaveById("_ActionId-1").replace().log("validator skipped: covered by the schema test");   // isolate the logic
        });
        AdviceWith.adviceWith(context, "{{ProxyName}}-updateContributor", a -> a.weaveById("_ActionId-16").replace().to("mock:core"));
        AdviceWith.adviceWith(context, "{{ProxyName}}-publishAudit", a -> a.weaveById("publish-audit").replace().to("mock:audit"));
        context.start();
        core = context.getEndpoint("mock:core", MockEndpoint.class);
        member = context.getEndpoint("mock:member", MockEndpoint.class);
        audit = context.getEndpoint("mock:audit", MockEndpoint.class);
    }

    String fixture(String name) throws Exception { return Files.readString(FIXTURES.resolve(name)); }

    /** T-01 getContributor, member ACTIVE: transform applied, bare payload routed to core, audit published once, InOnly. */
    @Test
    void getContributor_activeMember_isTransformedRoutedAndAudited() throws Exception {
        member.whenAnyExchangeReceived(e -> e.getMessage().setBody(fixture("backend/MemberLookupBS/lookupMember-active-response.xml")));
        core.whenAnyExchangeReceived(e -> e.getMessage().setBody(fixture("backend/ContributorCoreBS/getContributor-response.xml")));
        core.expectedMessageCount(1);
        core.message(0).header("X-Correlation-Id").isEqualTo("test-correlation");
        audit.expectedMessageCount(1);
        audit.message(0).exchangePattern().isEqualTo(ExchangePattern.InOnly);

        String reply = template.requestBodyAndHeaders("direct:in", fixture("01-getContributor-active-input.xml"),
            Map.of(CxfConstants.OPERATION_NAME, "getContributor", "X-Correlation-Id", "test-correlation"), String.class);

        MockEndpoint.assertIsSatisfied(context);
        String sentToCore = core.getExchanges().get(0).getMessage().getBody(String.class);
        XmlAssert.assertThat(sentToCore).and(fixture("01-getContributor-active-expected-core-request.xml")).ignoreWhitespace().ignoreComments().areSimilar();
        assertThat(sentToCore).doesNotContain("<Body>");                         // the wrapper never reaches a backend
        XmlAssert.assertThat(reply).and(fixture("backend/ContributorCoreBS/getContributor-response.xml")).ignoreWhitespace().areSimilar();
    }

    /** T-02 getContributor, member INACTIVE: raise error AMN-4001, core never called, fault reply through the original XSLT. */
    @Test
    void getContributor_inactiveMember_raisesAmn4001_andDoesNotRouteToCore() throws Exception {
        member.whenAnyExchangeReceived(e -> e.getMessage().setBody(fixture("backend/MemberLookupBS/lookupMember-inactive-response.xml")));
        core.expectedMessageCount(0);
        audit.expectedMessageCount(0);

        var exchange = template.send("direct:in", e -> {
            e.getMessage().setBody(fixture("01-getContributor-active-input.xml"));
            e.getMessage().setHeader(CxfConstants.OPERATION_NAME, "getContributor");
        });

        MockEndpoint.assertIsSatisfied(context);
        assertThat(exchange.getMessage().getHeader("osb.fault.errorCode", String.class)).isEqualTo("AMN-4001");
        XmlAssert.assertThat(exchange.getMessage().getBody(String.class)).and(fixture("02-fault-amn4001-expected.xml")).ignoreWhitespace().areSimilar();
    }

    /** T-03 updateContributor: pass-through to core with the right operation and a bare payload. */
    @Test
    void updateContributor_isRoutedToCore_withOperationHeader() throws Exception {
        core.expectedMessageCount(1);
        core.message(0).header(CxfConstants.OPERATION_NAME).isEqualTo("updateContributor");
        template.sendBodyAndHeader("direct:in", fixture("03-updateContributor-input.xml"), CxfConstants.OPERATION_NAME, "updateContributor");
        MockEndpoint.assertIsSatisfied(context);
        assertThat(core.getExchanges().get(0).getMessage().getBody(String.class)).doesNotContain("<Body>");
    }

    /** T-04 unknown operation: OSB-380002 fault, nothing called. */
    @Test
    void unknownOperation_isRejected() throws Exception {
        core.expectedMessageCount(0);
        var exchange = template.send("direct:in", e -> {
            e.getMessage().setBody(fixture("03-updateContributor-input.xml"));
            e.getMessage().setHeader(CxfConstants.OPERATION_NAME, "deleteContributor");
        });
        MockEndpoint.assertIsSatisfied(context);
        assertThat(exchange.getMessage().getHeader("osb.fault.errorCode", String.class)).isEqualTo("OSB-380002");
    }

    /** T-05 service error handler: a backend failure maps through the original fault XSLT and alerts once. */
    @Test
    void coreFailure_isMappedByTheOriginalFaultXslt() throws Exception {
        member.whenAnyExchangeReceived(e -> e.getMessage().setBody(fixture("backend/MemberLookupBS/lookupMember-active-response.xml")));
        core.whenAnyExchangeReceived(e -> { throw new java.net.ConnectException("core down"); });
        var exchange = template.send("direct:in", e -> {
            e.getMessage().setBody(fixture("01-getContributor-active-input.xml"));
            e.getMessage().setHeader(CxfConstants.OPERATION_NAME, "getContributor");
        });
        assertThat(exchange.getMessage().getHeader("osb.fault.errorCode", String.class)).isEqualTo("OSB-380001");
        assertThat(exchange.getMessage().getBody(String.class)).contains("Fault");
    }
}
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_OSBROUTETESTTEMPLATE_JAVA
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/java/OsbSupport.java")"
cat > '.pi/skills/osb-to-camel/assets/templates/java/OsbSupport.java' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_OSBSUPPORT_JAVA'
package {{package}}.osb;

import net.sf.saxon.s9api.Processor;
import net.sf.saxon.s9api.QName;
import net.sf.saxon.s9api.SaxonApiException;
import net.sf.saxon.s9api.XQueryCompiler;
import net.sf.saxon.s9api.XQueryEvaluator;
import net.sf.saxon.s9api.XQueryExecutable;
import net.sf.saxon.s9api.XdmAtomicValue;
import net.sf.saxon.s9api.XdmItem;
import net.sf.saxon.s9api.XdmNode;
import net.sf.saxon.s9api.XdmValue;
import org.apache.camel.Exchange;
import org.apache.camel.Expression;
import org.apache.camel.Predicate;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;

import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.dom.DOMSource;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * TEMPLATE: the support classes every migrated OSB module shares. Split into one file per class in the module.
 *
 * Why they exist: OSB expressions assume a context that Camel does not provide out of the box.
 *  - OSB's $body is the SOAP Body CONTENT; Camel's body is whatever the component delivered.
 *  - OSB expressions name pipeline variables directly ($memberResp); Camel's xquery language binds the message as the
 *    context item and headers as $in.headers.<name>, so "$body/ns:x" is an undeclared variable there.
 *  - OSB's $fault is an element with errorCode/reason/details/location; Camel has an exception on the exchange.
 *
 * The rule the templates follow: run every OSB expression, inline or stored, through {@link OsbXQuery} (Saxon s9api),
 * which binds $body to the <Body>-wrapped document, every exchange property by its OSB variable name, and $inbound /
 * $fault to small context elements. Zero edits to OSB expressions. Camel's own xquery()/xpath() languages are fine for
 * expressions you write yourself, never for copied OSB ones.
 */
public final class OsbSupport {
    private OsbSupport() {}

    static final String CTX = "http://www.bea.com/wli/sb/context";
    static final String TP = "http://www.bea.com/wli/sb/transports";
    static final String HTTP = "http://www.bea.com/wli/sb/transports/http";

    static Document newDocument() throws Exception {
        DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
        f.setNamespaceAware(true);
        f.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        return f.newDocumentBuilder().newDocument();
    }

    // ------------------------------------------------------------------------------------------------ body wrapper
    /**
     * OSB $body semantics. wrap() runs once at the inbound: it captures the transport headers as properties
     * (osb.inbound.*) and wraps the payload in <Body>. unwrap() runs BEFORE EVERY OUTBOUND CALL (route node, service
     * callout, publish) so the backend receives the bare payload, and rewrap() runs after a request-response call so
     * the response pipeline sees the backend response under $body again. The final unwrap() is the reply.
     */
    public static final class OsbBodyWrapper {
        public static final String WRAPPER = "Body";

        public static org.apache.camel.Processor wrap() {
            return exchange -> {
                exchange.getMessage().getHeaders().forEach((k, v) -> exchange.setProperty("osb.inbound." + k, v));
                rewrap().process(exchange);
            };
        }

        public static org.apache.camel.Processor rewrap() {
            return exchange -> {
                Document payload = exchange.getMessage().getBody(Document.class);  // Camel converts CxfPayload/String/Source
                Document doc = newDocument();
                Element body = doc.createElement(WRAPPER);
                doc.appendChild(body);
                if (payload != null && payload.getDocumentElement() != null) {
                    body.appendChild(doc.importNode(payload.getDocumentElement(), true));
                }
                exchange.getMessage().setBody(doc);
            };
        }

        public static org.apache.camel.Processor unwrap() {
            return exchange -> {
                Document doc = exchange.getMessage().getBody(Document.class);
                if (doc == null || doc.getDocumentElement() == null) return;
                Element root = doc.getDocumentElement();
                if (!WRAPPER.equals(root.getLocalName())) return;
                Node first = root.getFirstChild();
                while (first != null && first.getNodeType() != Node.ELEMENT_NODE) first = first.getNextSibling();
                if (first == null) { exchange.getMessage().setBody(null); return; }
                Document out = newDocument();
                out.appendChild(out.importNode(first, true));
                exchange.getMessage().setBody(out);
            };
        }
    }

    // ------------------------------------------------------------------------------------------------ OSB XQuery
    /**
     * Compiles an OSB XQuery expression once and evaluates it against the exchange with OSB's variable semantics.
     * Usage in a RouteBuilder:
     *   .setProperty("contributorId", OsbXQuery.of("$body/ns:getContributorRequest/ns:contributorId/text()").ns(NS).asString())
     *   .when(OsbXQuery.of("$memberResp/mem:lookupMemberResponse/mem:status/text() = 'ACTIVE'").ns(NS).asPredicate())
     *   .setBody(OsbXQuery.of("<audit><id>{ $contributorId }</id></audit>").ns(NS).asNode())
     *   .process(OsbXQuery.resource("osb/P/Transform/MemberToContributor.xqy").ns(NS).param("member", "memberResp", "/mem:lookupMemberResponse").param("contributorId", "contributorId").replaceBodyContentsOnly())
     * Every $name in the expression that is not body/header/inbound/outbound/fault/operation is bound from the exchange
     * property of that name (a DOM Node for element values, an atomic for strings/numbers). Stored queries that declare
     * "declare variable $x external;" are bound the same way, by name.
     */
    public static final class OsbXQuery {
        private static final Processor SAXON = new Processor(false);
        private static final Set<String> BUILTIN = Set.of("body", "header", "inbound", "outbound", "fault", "operation", "attachments", "messageID");
        private static final Pattern VAR = Pattern.compile("\\$([A-Za-z_][A-Za-z0-9_.-]*)");

        private final String source;
        private final boolean stored;                 // stored .xqy: declares its own externals; inline: we declare them
        private final Map<String, String> namespaces = new LinkedHashMap<>();
        private final Map<String, String[]> params = new LinkedHashMap<>();   // param -> {propertyName, xpathWithinProperty}
        private XQueryExecutable compiled;

        private OsbXQuery(String source, boolean stored) { this.source = source; this.stored = stored; }
        public static OsbXQuery of(String inlineExpression) { return new OsbXQuery(inlineExpression, false); }
        public static OsbXQuery resource(String classpath) {
            try (InputStream in = OsbSupport.class.getClassLoader().getResourceAsStream(classpath)) {
                if (in == null) throw new IllegalArgumentException("XQuery resource not found: " + classpath);
                return new OsbXQuery(new String(in.readAllBytes(), StandardCharsets.UTF_8), true);
            } catch (java.io.IOException e) { throw new IllegalStateException(e); }
        }
        public OsbXQuery ns(Map<String, String> prefixToUri) { namespaces.putAll(prefixToUri); return this; }
        public OsbXQuery param(String name, String property) { params.put(name, new String[]{property, null}); return this; }
        public OsbXQuery param(String name, String property, String xpath) { params.put(name, new String[]{property, xpath}); return this; }

        private synchronized XQueryExecutable compile() throws SaxonApiException {
            if (compiled != null) return compiled;
            XQueryCompiler c = SAXON.newXQueryCompiler();
            namespaces.forEach(c::declareNamespace);
            String text = source;
            if (!stored) {
                StringBuilder prolog = new StringBuilder();
                for (String v : referencedVariables()) prolog.append("declare variable $").append(v).append(" external;\n");
                text = prolog + source;
            }
            compiled = c.compile(text);
            return compiled;
        }

        private Set<String> referencedVariables() {
            Set<String> out = new java.util.LinkedHashSet<>();
            Matcher m = VAR.matcher(source);
            while (m.find()) out.add(m.group(1));
            return out;
        }

        public XdmValue evaluate(Exchange exchange) throws Exception {
            XQueryEvaluator ev = compile().load();
            for (String v : stored ? params.keySet() : referencedVariables()) {
                Object value;
                if (stored) {
                    String[] p = params.get(v);
                    value = exchange.getProperty(p[0]);
                    if (value instanceof Node n && p[1] != null) value = selectWithin(n, p[1]);
                } else if ("body".equals(v)) {
                    value = exchange.getMessage().getBody(Document.class);
                } else if ("inbound".equals(v)) {
                    value = inboundContext(exchange);
                } else if ("fault".equals(v)) {
                    value = exchange.getProperty("osb.fault.element");
                } else if ("operation".equals(v)) {
                    value = exchange.getProperty("osb.operation");
                } else if (BUILTIN.contains(v)) {
                    value = null;
                } else {
                    value = exchange.getProperty(v);
                }
                ev.setExternalVariable(new QName(v), toXdm(value));
            }
            return ev.evaluate();
        }

        /** The OSB $body/... path inside a stored-query parameter (<con1:path>$memberResp/mem:lookupMemberResponse</con1:path>). */
        private Object selectWithin(Node n, String xpath) throws Exception {
            OsbXQuery sub = OsbXQuery.of(xpath.replaceFirst("^\\$[A-Za-z_][\\w.-]*", "\\$v")).ns(namespaces);
            XQueryEvaluator ev = sub.compile().load();
            ev.setExternalVariable(new QName("v"), toXdm(n));
            XdmValue r = ev.evaluate();
            return r.size() == 0 ? null : r;
        }

        private static XdmValue toXdm(Object value) throws SaxonApiException {
            if (value == null) return XdmValue.makeSequence(java.util.List.of());
            if (value instanceof XdmValue x) return x;
            if (value instanceof Node n) {
                XdmNode node = SAXON.newDocumentBuilder().build(new DOMSource(n));
                // bind the element, not the document node, so $var/child::x works as it did in OSB
                return n.getNodeType() == Node.DOCUMENT_NODE && node.axisIterator(net.sf.saxon.s9api.Axis.CHILD).hasNext()
                    ? node.axisIterator(net.sf.saxon.s9api.Axis.CHILD).next() : node;
            }
            if (value instanceof String s) return new XdmAtomicValue(s);
            if (value instanceof Integer i) return new XdmAtomicValue(i);
            if (value instanceof Long l) return new XdmAtomicValue(l);
            if (value instanceof Boolean b) return new XdmAtomicValue(b);
            if (value instanceof java.math.BigDecimal d) return new XdmAtomicValue(d);
            return new XdmAtomicValue(String.valueOf(value));
        }

        /** $inbound/ctx:transport/ctx:request/tp:headers/http:<Name> built from the captured inbound headers. */
        private static Document inboundContext(Exchange exchange) throws Exception {
            Document d = newDocument();
            Element inbound = d.createElementNS(CTX, "ctx:inbound"); d.appendChild(inbound);
            Element transport = d.createElementNS(CTX, "ctx:transport"); inbound.appendChild(transport);
            Element request = d.createElementNS(CTX, "ctx:request"); transport.appendChild(request);
            Element headers = d.createElementNS(TP, "tp:headers"); request.appendChild(headers);
            for (Map.Entry<String, Object> e : exchange.getProperties().entrySet()) {
                if (e.getKey().startsWith("osb.inbound.") && e.getValue() != null) {
                    String name = e.getKey().substring("osb.inbound.".length());
                    if (!name.matches("[A-Za-z_][A-Za-z0-9_.-]*")) continue;
                    Element h = d.createElementNS(HTTP, "http:" + name);
                    h.setTextContent(String.valueOf(e.getValue()));
                    headers.appendChild(h);
                }
            }
            Element service = d.createElementNS(CTX, "ctx:service"); inbound.appendChild(service);
            Element op = d.createElementNS(CTX, "ctx:operation"); op.setTextContent(String.valueOf(exchange.getProperty("osb.operation", ""))); service.appendChild(op);
            return d;
        }

        // ---- adapters for the Camel DSL
        public Expression asString() {
            return new Expression() {
                @Override public <T> T evaluate(Exchange exchange, Class<T> type) {
                    try { XdmValue v = OsbXQuery.this.evaluate(exchange); return type.cast(v.size() == 0 ? null : v.itemAt(0).getStringValue()); }
                    catch (Exception e) { throw new RuntimeException(e); }
                }
            };
        }
        public Expression asNode() {
            return new Expression() {
                @Override public <T> T evaluate(Exchange exchange, Class<T> type) {
                    try {
                        XdmValue v = OsbXQuery.this.evaluate(exchange);
                        if (v.size() == 0) return null;
                        XdmItem item = v.itemAt(0);
                        Node n = net.sf.saxon.dom.NodeOverNodeInfo.wrap(((XdmNode) item).getUnderlyingNode());
                        Document d = newDocument(); d.appendChild(d.importNode(n, true));
                        return type.cast(d);
                    } catch (Exception e) { throw new RuntimeException(e); }
                }
            };
        }
        public Predicate asPredicate() {
            return exchange -> {
                try { XdmValue v = OsbXQuery.this.evaluate(exchange); return v.size() > 0 && ((XdmAtomicValue) v.itemAt(0)).getBooleanValue(); }
                catch (Exception e) { throw new RuntimeException(e); }
            };
        }
        /** OSB "Replace ... contents-only=true" on $body: keep the <Body> wrapper, replace its children with the result. */
        public org.apache.camel.Processor replaceBodyContentsOnly() {
            return exchange -> {
                Document result = asNode().evaluate(exchange, Document.class);
                Document body = exchange.getMessage().getBody(Document.class);
                Element wrapper = body.getDocumentElement();
                while (wrapper.getFirstChild() != null) wrapper.removeChild(wrapper.getFirstChild());
                if (result != null) wrapper.appendChild(body.importNode(result.getDocumentElement(), true));
            };
        }
        /** OSB "Replace ... contents-only=false" on $body: the result becomes the whole payload (re-wrapped). */
        public org.apache.camel.Processor replaceBody() {
            return exchange -> {
                Document result = asNode().evaluate(exchange, Document.class);
                exchange.getMessage().setBody(result);
                OsbBodyWrapper.rewrap().process(exchange);
            };
        }
    }

    // ------------------------------------------------------------------------------------------------ faults
    /** Raised by OSB "Raise Error" actions and by the processors; carries the contractual error code. */
    public static class OsbFaultException extends RuntimeException {
        private final String errorCode;
        public OsbFaultException(String errorCode, String reason) { super(reason); this.errorCode = errorCode; }
        public String getErrorCode() { return errorCode; }
    }

    /**
     * Builds the $fault equivalents: headers osb.fault.* and a <ctx:fault> element (property osb.fault.element and the
     * message body), so the original fault XSLT runs on the input it had in OSB. Codes follow OSB 12c ranges; user codes
     * pass through unchanged.
     */
    public static final class OsbFaultProcessor implements org.apache.camel.Processor {
        @Override
        public void process(Exchange exchange) throws Exception {
            Throwable t = exchange.getProperty(Exchange.EXCEPTION_CAUGHT, Throwable.class);
            String code = (t instanceof OsbFaultException f) ? f.getErrorCode() : codeFor(t);
            String reason = t == null ? "unknown" : String.valueOf(t.getMessage());
            exchange.getMessage().setHeader("osb.fault.errorCode", code);
            exchange.getMessage().setHeader("osb.fault.reason", reason);
            exchange.getMessage().setHeader("osb.fault.location.node", exchange.getProperty(Exchange.FAILURE_ROUTE_ID));
            exchange.getMessage().setHeader("osb.fault.java-exception", t == null ? "" : t.getClass().getName());
            Document doc = newDocument();
            Element fault = doc.createElementNS(CTX, "ctx:fault"); doc.appendChild(fault);
            Element ec = doc.createElementNS(CTX, "ctx:errorCode"); ec.setTextContent(code); fault.appendChild(ec);
            Element rs = doc.createElementNS(CTX, "ctx:reason"); rs.setTextContent(reason); fault.appendChild(rs);
            Element loc = doc.createElementNS(CTX, "ctx:location"); fault.appendChild(loc);
            Element node = doc.createElementNS(CTX, "ctx:node"); node.setTextContent(String.valueOf(exchange.getProperty(Exchange.FAILURE_ROUTE_ID, ""))); loc.appendChild(node);
            exchange.setProperty("osb.fault.element", doc);
            exchange.getMessage().setBody(doc);
        }

        /** Exception type -> nearest OSB range: transport 380000s, pipeline runtime 382000s, actions 382500s. */
        static String codeFor(Throwable t) {
            if (t == null) return "OSB-382000";
            String n = t.getClass().getName();
            if (n.contains("Connect") || n.contains("Timeout") || n.contains("Http")) return "OSB-380001";
            if (n.contains("Validation") || n.contains("SAXParse")) return "OSB-382505";
            return "OSB-382000";
        }

        /** OSB "Reply with failure": the body produced by the fault XSLT is returned as a SOAP fault. */
        public static void replyWithSoapFault(Exchange exchange) {
            // camel-cxf PAYLOAD mode: a SoapFault set as the exception (or a <soapenv:Fault> body with HTTP 500) is
            // returned as a fault envelope. Project-specific; see references/osb-action-mapping.md, "reply isErrorReply".
            exchange.getMessage().setHeader(Exchange.HTTP_RESPONSE_CODE, 500);
        }
    }
}
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_OSBSUPPORT_JAVA
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/java/ParityReplayTestTemplate.java")"
cat > '.pi/skills/osb-to-camel/assets/templates/java/ParityReplayTestTemplate.java' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_PARITYREPLAYTESTTEMPLATE_JAVA'
package {{package}}.{{project_pkg}};

import com.github.tomakehurst.wiremock.junit5.WireMockExtension;
import org.apache.camel.ProducerTemplate;
import org.apache.camel.component.cxf.common.message.CxfConstants;
import org.apache.camel.test.spring.junit5.CamelSpringBootTest;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.extension.RegisterExtension;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.xmlunit.builder.DiffBuilder;
import org.xmlunit.diff.Diff;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import static com.github.tomakehurst.wiremock.client.WireMock.*;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.wireMockConfig;
import static org.assertj.core.api.Assertions.assertThat;

/**
 * TEMPLATE: parity replay. Each folder under src/test/resources/parity/{{flow}}/<NN>/ holds a recorded OSB exchange:
 *   request.xml, response.xml, backend/<BusinessService>/request.xml + response.xml, and optionally ignore-fields.txt.
 * WireMock replays the backend responses; the route's response must be similar to the recorded OSB response, and the
 * request the route sent to each backend must be similar to the recorded backend request.
 * Without fixtures the test is skipped with a visible reason: parity is then "not proven", and the record says so.
 */
@CamelSpringBootTest
@SpringBootTest(classes = {{ProxyName}}Route.class)
@ActiveProfiles("test")
class {{ProxyName}}ParityReplayTest {

    static final Path PARITY = Path.of("src/test/resources/parity/{{flow}}");

    @RegisterExtension
    static WireMockExtension backends = WireMockExtension.newInstance().options(wireMockConfig().dynamicPort()).build();

    @DynamicPropertySource
    static void backendsToWireMock(DynamicPropertyRegistry r) {
        r.add("osb.business.ContributorCoreBS.url", () -> backends.baseUrl() + "/ContributorService");
        r.add("osb.business.MemberLookupBS.url", () -> backends.baseUrl() + "/MemberLookup/v2");
    }

    @Autowired ProducerTemplate template;

    static Stream<Path> recordings() throws Exception {
        if (!Files.isDirectory(PARITY)) return Stream.empty();
        try (var s = Files.list(PARITY)) { return s.filter(Files::isDirectory).sorted().toList().stream(); }
    }

    @ParameterizedTest(name = "recorded exchange {0}")
    @MethodSource("recordings")
    void replayedExchange_matchesRecordedResponse(Path rec) throws Exception {
        Assumptions.assumeTrue(Files.exists(rec.resolve("response.xml")), "no recorded OSB response in " + rec);
        backends.resetAll();
        // replay every recorded backend response
        try (var s = Files.list(rec.resolve("backend"))) {
            for (Path b : s.toList()) {
                String path = b.getFileName().toString().equals("ContributorCoreBS") ? "/ContributorService" : "/MemberLookup/v2";
                backends.stubFor(post(urlPathEqualTo(path)).willReturn(okXml(Files.readString(b.resolve("response.xml")))));
            }
        }
        String operation = Files.readString(rec.resolve("operation.txt")).trim();
        var exchange = template.send("cxf:bean:{{proxyName}}Endpoint?dataFormat=PAYLOAD", e -> {
            e.getMessage().setBody(Files.readString(rec.resolve("request.xml")));
            e.getMessage().setHeader(CxfConstants.OPERATION_NAME, operation);
        });
        List<String> ignore = Files.exists(rec.resolve("ignore-fields.txt")) ? Files.readAllLines(rec.resolve("ignore-fields.txt")) : List.of();

        Diff diff = DiffBuilder.compare(Files.readString(rec.resolve("response.xml")))
            .withTest(exchange.getMessage().getBody(String.class))
            .ignoreWhitespace().ignoreComments().checkForSimilar()
            .withNodeFilter(n -> ignore.stream().noneMatch(x -> x.equals(n.getLocalName())))
            .build();
        assertThat(diff.hasDifferences()).as(diff.fullDescription()).isFalse();

        // and the backend saw what OSB sent it
        try (var s = Files.list(rec.resolve("backend"))) {
            for (Path b : s.toList()) {
                String path = b.getFileName().toString().equals("ContributorCoreBS") ? "/ContributorService" : "/MemberLookup/v2";
                var sent = backends.findAll(postRequestedFor(urlPathEqualTo(path)));
                assertThat(sent).as("backend " + b.getFileName() + " was called").isNotEmpty();
                Diff bd = DiffBuilder.compare(Files.readString(b.resolve("request.xml"))).withTest(sent.get(0).getBodyAsString())
                    .ignoreWhitespace().checkForSimilar().withNodeFilter(n -> ignore.stream().noneMatch(x -> x.equals(n.getLocalName()))).build();
                assertThat(bd.hasDifferences()).as(bd.fullDescription()).isFalse();
            }
        }
    }
}
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_PARITYREPLAYTESTTEMPLATE_JAVA
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/java/TransformGoldenTestTemplate.java")"
cat > '.pi/skills/osb-to-camel/assets/templates/java/TransformGoldenTestTemplate.java' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_TRANSFORMGOLDENTESTTEMPLATE_JAVA'
package {{package}}.{{project_pkg}};

import net.sf.saxon.s9api.Processor;
import net.sf.saxon.s9api.QName;
import net.sf.saxon.s9api.XQueryCompiler;
import net.sf.saxon.s9api.XQueryEvaluator;
import net.sf.saxon.s9api.XdmNode;
import net.sf.saxon.s9api.XdmValue;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.xmlunit.builder.DiffBuilder;
import org.xmlunit.diff.Diff;

import javax.xml.transform.stream.StreamSource;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * TEMPLATE: golden test for one OSB transform. The expected output is never hand-written: it is what the ORIGINAL
 * query (untouched copy under src/test/resources/osb-original/, with the fn-bea shim imported) produces for the
 * fixture. The migrated query under src/main/resources/osb/ must produce the same, modulo the ignore list.
 *
 * Fixture layout: src/test/resources/fixtures/{{flow}}/transforms/{{TransformName}}/<NN>-<desc>/params/<param>.xml
 *                 ... plus ignore-fields.txt (one XPath per line) next to the fixture folders.
 */
class {{TransformName}}GoldenTest {

    static final Path FIXTURES = Path.of("src/test/resources/fixtures/{{flow}}/transforms/{{TransformName}}");
    static final Path ORIGINAL = Path.of("src/test/resources/osb-original/{{project}}/Transform/{{TransformName}}.xqy");
    static final Path MIGRATED = Path.of("src/main/resources/osb/{{project}}/Transform/{{TransformName}}.xqy");
    static final Path SHIM_DIR = Path.of("src/test/resources/osb-original/shim/");   // fn-bea-shim.xqy lives here
    static final String SHIM_IMPORT = "import module namespace fn-bea = \"http://www.bea.com/xquery/xquery-functions\" at \"fn-bea-shim.xqy\";\n";

    static Stream<Path> fixtures() throws Exception {
        try (var s = Files.list(FIXTURES)) { return s.filter(Files::isDirectory).sorted().toList().stream(); }
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtures")
    void migratedEqualsOriginal(Path fixture) throws Exception {
        String expected = run(ORIGINAL, fixture, true);     // original + shim = the OSB behaviour
        String actual = run(MIGRATED, fixture, false);      // what the route will execute
        List<String> ignore = Files.exists(FIXTURES.resolve("ignore-fields.txt"))
            ? Files.readAllLines(FIXTURES.resolve("ignore-fields.txt")) : List.of();

        Diff diff = DiffBuilder.compare(expected).withTest(actual)
            .ignoreWhitespace().ignoreComments().checkForSimilar()
            .withNodeFilter(node -> ignore.stream().noneMatch(x -> x.equals(node.getLocalName())))  // simple name filter; XPath filter in the project helper
            .build();
        assertThat(diff.hasDifferences()).as(diff.fullDescription()).isFalse();
    }

    /** Compiles the query (prepending the shim import for the original), binds every params/<name>.xml as $<name>. */
    static String run(Path query, Path fixture, boolean withShim) throws Exception {
        Processor saxon = new Processor(false);
        XQueryCompiler compiler = saxon.newXQueryCompiler();
        compiler.setBaseURI(SHIM_DIR.toUri());
        String text = Files.readString(query);
        if (withShim) {
            // insert after the version declaration so the prolog stays valid
            int cut = text.indexOf(';') + 1;
            text = text.substring(0, cut) + "\n" + SHIM_IMPORT + text.substring(cut);
        }
        XQueryEvaluator ev = compiler.compile(text).load();
        Path params = fixture.resolve("params");
        if (Files.isDirectory(params)) {
            try (var s = Files.list(params)) {
                for (Path p : s.toList()) {
                    String name = p.getFileName().toString().replaceFirst("\\.(xml|txt)$", "");
                    if (p.toString().endsWith(".xml")) {
                        XdmNode doc = saxon.newDocumentBuilder().build(new StreamSource(p.toFile()));
                        ev.setExternalVariable(new QName(name), doc.axisIterator(net.sf.saxon.s9api.Axis.CHILD).next());
                    } else {
                        ev.setExternalVariable(new QName(name), new net.sf.saxon.s9api.XdmAtomicValue(Files.readString(p).trim()));
                    }
                }
            }
        }
        XdmValue result = ev.evaluate();
        return result.toString();
    }
}
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_JAVA_TRANSFORMGOLDENTESTTEMPLATE_JAVA
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/pom-dependencies.xml")"
cat > '.pi/skills/osb-to-camel/assets/templates/pom-dependencies.xml' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_POM_DEPENDENCIES_XML'
<!--
  Dependency fragment for a migrated OSB module (Camel on Spring Boot, Java DSL).
  Versions come from a property block that mirrors references/versions.md; pin them there, not here.
  Only the starters a flow needs are kept; the scaffold lists the ones the card requires.
-->
<properties>
  <camel.version><!-- versions.md --></camel.version>
  <spring-boot.version><!-- versions.md --></spring-boot.version>
  <wiremock.version><!-- versions.md --></wiremock.version>
  <testcontainers.version><!-- versions.md --></testcontainers.version>
  <xmlunit.version><!-- versions.md --></xmlunit.version>
</properties>

<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.apache.camel.springboot</groupId>
      <artifactId>camel-spring-boot-bom</artifactId>
      <version>${camel.version}</version>
      <type>pom</type>
      <scope>import</scope>
    </dependency>
    <dependency>
      <groupId>org.testcontainers</groupId>
      <artifactId>testcontainers-bom</artifactId>
      <version>${testcontainers.version}</version>
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>

<dependencies>
  <!-- runtime: the route, the inbound and outbound components the card selected -->
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-spring-boot-starter</artifactId></dependency>
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-cxf-soap-starter</artifactId></dependency>        <!-- SOAP in/out -->
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-platform-http-starter</artifactId></dependency>   <!-- REST / any-XML in -->
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-http-starter</artifactId></dependency>            <!-- REST / XML out -->
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-saxon-starter</artifactId></dependency>           <!-- XQuery (OSB transforms) -->
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-xslt-saxon-starter</artifactId></dependency>      <!-- XSLT (OSB transforms) -->
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-validator-starter</artifactId></dependency>       <!-- OSB validate action -->
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-amqp-starter</artifactId></dependency>            <!-- JMS over AMQP 1.0 to AMQ Broker -->
  <dependency><groupId>org.apache.camel.springboot</groupId><artifactId>camel-micrometer-starter</artifactId></dependency>      <!-- alert counters, route metrics -->

  <!-- tests -->
  <dependency><groupId>org.apache.camel</groupId><artifactId>camel-test-spring-junit5</artifactId><scope>test</scope></dependency>
  <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
  <dependency><groupId>org.wiremock</groupId><artifactId>wiremock-standalone</artifactId><version>${wiremock.version}</version><scope>test</scope></dependency>
  <dependency><groupId>org.testcontainers</groupId><artifactId>activemq</artifactId><scope>test</scope></dependency>             <!-- ArtemisContainer -->
  <dependency><groupId>org.testcontainers</groupId><artifactId>junit-jupiter</artifactId><scope>test</scope></dependency>
  <dependency><groupId>org.xmlunit</groupId><artifactId>xmlunit-core</artifactId><version>${xmlunit.version}</version><scope>test</scope></dependency>
  <dependency><groupId>org.xmlunit</groupId><artifactId>xmlunit-assertj3</artifactId><version>${xmlunit.version}</version><scope>test</scope></dependency>
  <!-- Saxon s9api for the golden tests comes transitively with camel-saxon; declare it explicitly only if the team's
       dependency analysis demands direct declarations -->
</dependencies>
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_POM_DEPENDENCIES_XML
mkdir -p "$(dirname ".pi/skills/osb-to-camel/assets/templates/xquery/fn-bea-shim.xqy")"
cat > '.pi/skills/osb-to-camel/assets/templates/xquery/fn-bea-shim.xqy' <<'KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_XQUERY_FN_BEA_SHIM_XQY'
xquery version "3.1";
(:
  fn-bea shim: the Oracle Service Bus XQuery extension functions that OSB flows use most, implemented in XQuery 3.1
  under the ORIGINAL namespace URI, so that an unchanged OSB query runs under Saxon after one added line:

      import module namespace fn-bea = "http://www.bea.com/xquery/xquery-functions" at "fn-bea-shim.xqy";

  Policy: a function either behaves like OSB for the patterns listed, or raises a clear error. It never guesses.
  Functions that depend on the OSB runtime (SQL, credentials, users, groups) are declared here only to fail with a
  message that names the replacement, so a golden test fails loudly instead of silently differing.
:)
module namespace fn-bea = "http://www.bea.com/xquery/xquery-functions";

(: ---------------------------------------------------------------- date / time formatting ---------------------- :)
(: Java SimpleDateFormat pattern -> XPath format-date picture. Covers the tokens OSB flows use; unknown letters error. :)
declare %private function fn-bea:picture($fmt as xs:string) as xs:string {
  let $tokens := analyze-string($fmt, "('[^']*')|(y{1,4}|M{1,4}|d{1,2}|H{1,2}|h{1,2}|m{1,2}|s{1,2}|S{1,3}|a|E{1,4}|Z|X{1,3})|([^yMdHhmsSaEZX']+)")
  return string-join(
    for $m in $tokens/*
    return
      if ($m/self::*:non-match) then error(xs:QName("fn-bea:unsupported-pattern"), concat("fn-bea shim: pattern token not supported: ", string($m), " in ", $fmt))
      else if ($m/*:group[@nr=1]) then replace(substring($m, 2, string-length($m) - 2), "\[", "[[")      (: quoted literal :)
      else if ($m/*:group[@nr=3]) then replace(string($m), "\[", "[[")                                      (: separators :)
      else
        let $t := string($m) return
        switch (true())
          case starts-with($t, "yyyy") return "[Y0001]"
          case starts-with($t, "yy")   return "[Y01]"
          case $t = "y"                return "[Y]"
          case $t = "MMMM"             return "[MNn]"
          case $t = "MMM"              return "[MNn,*-3]"
          case starts-with($t, "MM")   return "[M01]"
          case $t = "M"                return "[M]"
          case $t = "dd"               return "[D01]"
          case $t = "d"                return "[D]"
          case $t = "HH"               return "[H01]"
          case $t = "H"                return "[H]"
          case $t = "hh"               return "[h01]"
          case $t = "h"                return "[h]"
          case $t = "mm"               return "[m01]"
          case $t = "m"                return "[m]"
          case $t = "ss"               return "[s01]"
          case $t = "s"                return "[s]"
          case $t = "SSS"              return "[f001]"
          case $t = "SS"               return "[f01]"
          case $t = "S"                return "[f1]"
          case $t = "a"                return "[PN]"
          case starts-with($t, "EEEE") return "[FNn]"
          case starts-with($t, "E")    return "[FNn,*-3]"
          case $t = "Z"                return "[Z0000]"
          case starts-with($t, "X")    return "[Z]"
          default return error(xs:QName("fn-bea:unsupported-pattern"), concat("fn-bea shim: token ", $t, " in ", $fmt))
  , "")
};

declare function fn-bea:date-to-string-with-format($fmt as xs:string, $date as xs:date?) as xs:string? {
  if (empty($date)) then () else format-date($date, fn-bea:picture($fmt))
};
declare function fn-bea:dateTime-to-string-with-format($fmt as xs:string, $dt as xs:dateTime?) as xs:string? {
  if (empty($dt)) then () else format-dateTime($dt, fn-bea:picture($fmt))
};
declare function fn-bea:time-to-string-with-format($fmt as xs:string, $t as xs:time?) as xs:string? {
  if (empty($t)) then () else format-time($t, fn-bea:picture($fmt))
};

(: Java pattern -> regex with named positions, for the parse direction. Common patterns only. :)
declare %private function fn-bea:parse-parts($fmt as xs:string, $s as xs:string) as map(xs:string, xs:string) {
  let $tokens := analyze-string($fmt, "(yyyy|yy|MM|dd|HH|mm|ss|SSS)|([^yMdHmsS]+)")
  let $names := for $m in $tokens/*:match[*:group[@nr=1]] return string($m)
  let $re := string-join(for $m in $tokens/* return
               if ($m/self::*:non-match) then error(xs:QName("fn-bea:unsupported-pattern"), concat("fn-bea shim parse: ", $fmt))
               else if ($m/*:group[@nr=1]) then (switch (string($m)) case "yyyy" return "(\d{4})" case "SSS" return "(\d{1,3})" default return "(\d{1,2})")
               else replace(string($m), "([.\\+*?\[\]^$(){}|/])", "\\$1"), "")
  let $a := analyze-string($s, concat("^", $re, "$"))
  return if (empty($a/*:match)) then error(xs:QName("fn-bea:parse-failed"), concat("fn-bea shim: '", $s, "' does not match '", $fmt, "'"))
         else map:merge(for $n at $i in $names return map { $n : string($a/*:match/*:group[@nr=$i]) })
};
declare %private function fn-bea:pad2($v as xs:string?) as xs:string { if (empty($v)) then "00" else format-number(xs:integer($v), "00") };

declare function fn-bea:date-from-string-with-format($fmt as xs:string, $s as xs:string?) as xs:date? {
  if (empty($s) or $s = "") then () else
  let $p := fn-bea:parse-parts($fmt, $s)
  let $y := if (map:contains($p, "yyyy")) then $p("yyyy") else concat("20", $p("yy"))
  return xs:date(concat($y, "-", fn-bea:pad2($p("MM")), "-", fn-bea:pad2($p("dd"))))
};
declare function fn-bea:dateTime-from-string-with-format($fmt as xs:string, $s as xs:string?) as xs:dateTime? {
  if (empty($s) or $s = "") then () else
  let $p := fn-bea:parse-parts($fmt, $s)
  let $y := if (map:contains($p, "yyyy")) then $p("yyyy") else concat("20", $p("yy"))
  return xs:dateTime(concat($y, "-", fn-bea:pad2($p("MM")), "-", fn-bea:pad2($p("dd")), "T",
                            fn-bea:pad2($p("HH")), ":", fn-bea:pad2($p("mm")), ":", fn-bea:pad2($p("ss"))))
};

(: ---------------------------------------------------------------- strings ------------------------------------- :)
(: OSB trim removes leading and trailing whitespace only; normalize-space would also collapse inner runs. :)
declare function fn-bea:trim($s as xs:string?) as xs:string? { if (empty($s)) then () else replace($s, "^\s+|\s+$", "") };
declare function fn-bea:trim-left($s as xs:string?) as xs:string? { if (empty($s)) then () else replace($s, "^\s+", "") };
declare function fn-bea:trim-right($s as xs:string?) as xs:string? { if (empty($s)) then () else replace($s, "\s+$", "") };

(: ---------------------------------------------------------------- XML in strings ---------------------------- :)
declare function fn-bea:inlinedXML($s as xs:string?) as node()* { if (empty($s)) then () else parse-xml($s)/node() };
declare function fn-bea:serialize($n as node()?) as xs:string? { if (empty($n)) then () else serialize($n) };

(: ---------------------------------------------------------------- identifiers ---------------------------------- :)
(: Not reproducible by definition; always in the parity ignore list. Prefer binding a Camel-generated header. :)
declare function fn-bea:uuid() as xs:string {
  let $g := random-number-generator()
  let $hex := function($n as xs:integer) as xs:string {
      string-join(for $i in 1 to $n return substring("0123456789abcdef", xs:integer(floor($g?permute(1 to 16)[1])), 1), "") }
  return concat($hex(8), "-", $hex(4), "-4", $hex(3), "-a", $hex(3), "-", $hex(12))
};
declare function fn-bea:generate-guid() as xs:string { fn-bea:uuid() };

(: ---------------------------------------------------------------- deliberately not implemented ---------------- :)
declare function fn-bea:execute-sql($ds as xs:string, $row as xs:QName, $sql as xs:string, $params as item()*) as element()* {
  error(xs:QName("fn-bea:not-implemented"), "fn-bea:execute-sql: replace with a sql: endpoint step before the transform and pass the rows as an external variable")
};
declare function fn-bea:lookupBasicCredentials($ref as xs:string) as element()? {
  error(xs:QName("fn-bea:not-implemented"), "fn-bea:lookupBasicCredentials: credentials come from Vault-delivered properties bound as external variables")
};
declare function fn-bea:isUserInGroup($user as xs:string, $group as xs:string) as xs:boolean {
  error(xs:QName("fn-bea:not-implemented"), "fn-bea:isUserInGroup: authorization moved to the gateway/mesh; record on the flow card")
};
declare function fn-bea:isUserInRole($user as xs:string, $role as xs:string) as xs:boolean {
  error(xs:QName("fn-bea:not-implemented"), "fn-bea:isUserInRole: authorization moved to the gateway/mesh; record on the flow card")
};
KIT_EOF__PI_SKILLS_OSB_TO_CAMEL_ASSETS_TEMPLATES_XQUERY_FN_BEA_SHIM_XQY
chmod +x .pi/skills/osb-to-camel/scripts/*.py 2>/dev/null || true
echo "installed: 12 files (skill osb-to-camel: assets/templates)"
